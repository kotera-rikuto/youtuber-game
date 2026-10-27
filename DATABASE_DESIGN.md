# 『YouTuberになろう！（仮）』データベース設計

> ステータス：非UI実装着手版
> 更新日：2026年10月27日
> DB：Supabase PostgreSQL
> 正本仕様：`docs/ゆーちゅーばーになろう（仮）_ゲーム仕様書.md`

図：`DATABASE_ERD.svg` / `DATABASE_ERD.png`（実行時データ）、`RULES_ERD.svg` / `RULES_ERD.png`（ルール構造）

## 1. 結論

書き込みモデルは、第3正規形を基本にして「現在状態」「入力」「確定履歴」「バージョン付きルール」を分離する。画面表示のために結合済みデータが必要な場合は、重複列を持つ通常テーブルを増やさず、PostgreSQL ViewまたはQuery/DALのDTOで組み立てる。

例外として、次の2種類だけは意図的なスナップショットを許可する。

- `run_state`：現在画面を高速に表示するための、ゲーム人生1件につき1行の現在値
- `week_results` と `video_calculations`：確定時点の結果を後から説明・再現するための変更不能な履歴

この例外は「正本がどちらか分からない重複」ではない。現在値の正本は `run_state`、過去の正本は週・動画履歴とし、`advanceWeek` が同じトランザクションで両方を更新する。

## 2. 現行案から修正した問題

| 現行案の問題 | 保守上のリスク | 見直し後 |
|---|---|---|
| `game_runs` に6能力を6列で保持 | 能力追加のたびにマイグレーションと全Query修正 | `run_abilities` を1能力1行に正規化 |
| カメラ・マイク・PCを3列で保持 | 機材種類追加に弱い | `run_equipment` を1機材1行に正規化 |
| `game_rule_versions.config` が巨大なJSONB | 型、FK、CHECK、差分レビューが効かない | ルール種別ごとの型付きテーブルへ分割 |
| 行動効果と解放条件をJSONBで保持 | 不正なキーや単位ミスをDBが検出できない | `action_rules` と `feature_rules` の型付き列へ移動 |
| AI点数帯の対応をプログラムだけで管理 | バランス変更時にコード改修が必要 | `idea_score_band_rules` でバージョン管理 |
| 企画の `status`、`published_week`、`deleted_at` が重複 | 矛盾した状態を作れる | 原本、キュー、消費を別テーブルへ分離 |
| 動画にプレイヤー企画とテンプレートを直接混在 | システム企画の周回制約を表現しづらい | `system_idea_cycles`と`system_idea_cycle_entries`で一巡順を保存 |
| 週次行動と週間結果に行動コードを重複 | 値が食い違う可能性 | `week_results.weekly_action_id` で確定行動を参照 |
| ルールマスタの一部だけバージョン付き | 過去プレイが現在のマスタを参照してしまう | すべてのバランス値を `rule_sets` 配下へ統一 |
| `game_events.payload` が数値結果の正本 | JSON構造変更で集計が壊れる | 数値結果は型付き履歴、JSONBは表示用補足だけ |
| 未確定の年齢カラムを先に追加 | 不要仕様がDBへ固定される | 年齢仕様が決まるまで作成しない |

## 3. データの区分

```text
不変に近い識別情報
  game_runs
       │ 1:1
       ▼
現在値の正本
  run_state ─ run_abilities ─ run_equipment ─ run_feature_unlocks
       │
       ├── プレイヤー入力：player_ideas / idea_queue_entries / weekly_actions
       │
       ├── 確定履歴：week_results / videos / video_calculations / occurred_events
       └── 終了履歴：game_terminations

全計算が参照するバージョン付きルール
  rule_sets ─ 各種 *_rules
```

## 4. コア・現在状態

### 4.1 `profiles`

Supabaseの`auth.users`と1対1で結ぶ任意のアプリプロフィール。初期版では「始める」押下時にSupabase匿名認証を自動実行し、登録画面を出さない。匿名ユーザーも`auth.users.id`を持つため、通常のFKとRLSをそのまま利用する。

| カラム | 型 | 制約 |
|---|---|---|
| `user_id` | `uuid` | PK、FK → `auth.users.id` |
| `display_name` | `text` | NULL可 |
| `created_at` | `timestamptz` | NOT NULL |

チュートリアルを実装するときは、JSONBではなく `tutorial_step_definitions` と `tutorial_progress(user_id, step_code, completed_at)` を追加する。

CookieにはSupabase匿名認証セッションだけを保持し、ゲームデータ本体や独自の所有者トークンは保存しない。`localStorage`は使用しない。`profiles`は初期版のゲーム開始に必須ではなく、作成する場合は`auth.users`作成トリガーで空行を生成する。

### 4.2 `game_runs`

ゲーム人生の識別情報と、途中で変わらない参照を持つ。

| カラム | 型 | 制約・意味 |
|---|---|---|
| `id` | `uuid` | PK |
| `user_id` | `uuid` | NOT NULL、FK → `auth.users.id` |
| `rule_set_id` | `uuid` | FK → `rule_sets.id`、開始後変更禁止 |
| `channel_rule_id` | `uuid` | FK → `channel_rules.id`、開始後変更禁止 |
| `channel_name` | `text` | 変更可能 |
| `status` | `text` | `playing / stage_cleared / cleared / game_over / abandoned` |
| `created_at` | `timestamptz` | NOT NULL |
| `completed_at` | `timestamptz` | NULL可 |

`channel_rule_id` が `rule_set_id` と同じルールセットに属することは制約トリガーで保証する。

`status IN ('playing', 'stage_cleared')`を進行中とみなし、`user_id`に部分一意インデックスを付ける。これにより1匿名ユーザーの進行中ゲームを最大1件にする。終了済み人生は同じ`user_id`に複数保持し、新規人生は常に新しい`game_runs.id`で作成する。

### 4.3 `run_state`

1ゲーム人生につき1行の現在値。1対1に分けることで、識別情報と高頻度更新行を分離する。

| カラム | 型 | 主な制約 |
|---|---|---|
| `run_id` | `uuid` | PK/FK → `game_runs.id` |
| `current_week` | `integer` | 1以上。「次に処理する週」 |
| `posting_frequency_rule_id` | `uuid` | FK → `posting_frequency_rules.id` |
| `cash` | `bigint` | 0以上 |
| `energy` | `smallint` | 0〜ルール上限 |
| `subscribers` | `bigint` | 0以上 |
| `cumulative_views` | `bigint` | 0以上 |
| `flame_count` | `smallint` | 0〜3 |
| `state_version` | `integer` | 楽観的ロック |
| `updated_at` | `timestamptz` | NOT NULL |

広告解放、コラボ解放などを個別の真偽列にせず、`run_feature_unlocks` へ保存する。能力ポイントも専用の付与履歴を正本とする。

### 4.4 `run_abilities`

| カラム | 型 | 制約 |
|---|---|---|
| `run_id` | `uuid` | FK → `game_runs.id` |
| `ability_code` | `text` | FK → `ability_definitions.code` |
| `value` | `smallint` | 0〜100 |

PKは `(run_id, ability_code)`。初期作成時に6能力を6行、値10で作成する。能力が将来追加されてもテーブル定義を変更しない。

### 4.5 `run_equipment`

| カラム | 型 | 制約 |
|---|---|---|
| `run_id` | `uuid` | FK → `game_runs.id` |
| `equipment_type_code` | `text` | FK → `equipment_types.code` |
| `equipment_tier_rule_id` | `uuid` | FK → `equipment_tier_rules.id` |
| `acquired_week` | `integer` | 0以上 |

PKは `(run_id, equipment_type_code)`。未所持は行なしで表現し、上位購入時は同じ行のティアルール参照を置換する。

### 4.6 `run_feature_unlocks`

広告、コラボ、企業案件などの解放履歴。

| カラム | 型 | 制約 |
|---|---|---|
| `run_id` | `uuid` | FK → `game_runs.id` |
| `feature_rule_id` | `uuid` | FK → `feature_rules.id` |
| `unlocked_week` | `integer` | 条件到達週 |
| `active_from_week` | `integer` | 実際に利用可能になる週 |

PKは `(run_id, feature_rule_id)`。登録者が減っても行を削除しないため、永続解放を自然に表現できる。

### 4.7 `run_conditions`

初期版の共通「体調不良」による活動不能履歴と現在状態を兼ねる。個別の病名は持たない。

| カラム | 型 | 意味 |
|---|---|---|
| `id` | `uuid` | PK |
| `run_id` | `uuid` | FK → `game_runs.id` |
| `health_risk_rule_id` | `uuid` | 発症時に使用した`health_risk_rules.id` |
| `started_week` | `integer` | 発症週 |
| `duration_weeks` | `smallint` | 発症時に均等抽選した期間 |
| `unavailable_from_week` | `integer` | 発症翌週 |
| `unavailable_through_week` | `integer` | 活動不能となる最終週、両端を含む |
| `recovered_at` | `timestamptz` | 回復確定日時、NULL可 |

例えば第10週に2週間の体調不良が発生した場合、`unavailable_from_week=11`、`unavailable_through_week=12`とする。活動不能週は体力+10だけを確定し、動画・行動・イベント・炎上・能力ポイント処理を行わない。

### 4.8 `run_goals`

| カラム | 型 | 制約 |
|---|---|---|
| `id` | `uuid` | PK |
| `run_id` | `uuid` | FK → `game_runs.id` |
| `goal_rule_id` | `uuid` | FK → `goal_rules.id` |
| `started_week` / `deadline_week` | `integer` | 累計週 |
| `achieved_week` | `integer` | NULL可 |
| `status` | `text` | `active / achieved / failed` |

`UNIQUE (run_id, goal_rule_id)` と、1ゲームにつき `active` が最大1行となる部分一意インデックスを付ける。

ステージ1は`started_week=1`、`deadline_week=156`。第N週にステージ達成した場合、次ステージは`started_week=N+1`、`deadline_week=N+156`とし、両端を含めて156週を確保する。

## 5. プレイヤー入力と変更履歴

### 5.1 `player_ideas`

作成された企画そのものを保持する。編集しないため、タイトルと説明は作成後不変。

| カラム | 型 | 意味 |
|---|---|---|
| `id` | `uuid` | PK |
| `run_id` | `uuid` | FK → `game_runs.id` |
| `title` | `text` | 1〜100文字 |
| `description` | `text` | NULL可 |
| `created_week` | `integer` | 週間3件制限に使用 |
| `deleted_at` | `timestamptz` | NULLなら未削除 |
| `created_at` | `timestamptz` | NOT NULL |

`status` と `published_week` は持たない。削除済みかは `deleted_at`、投稿済みかは `videos.player_idea_id` の存在で決まる。

### 5.2 `idea_evaluations`

| カラム | 型 | 制約 |
|---|---|---|
| `idea_id` | `uuid` | PK/FK → `player_ideas.id` |
| `score` | `smallint` | 0〜100 |
| `evaluation_status` | `text` | `completed / fallback` |
| `model` / `prompt_version` | `text` | 監査用 |
| `evaluated_at` | `timestamptz` | NOT NULL |

倍率と転換率は保存せず、ゲームの `rule_set_id` に属する `idea_score_band_rules` から決定する。

### 5.3 `idea_queue_entries`

投稿待ちキューだけを表す現在テーブル。

| カラム | 型 | 制約 |
|---|---|---|
| `idea_id` | `uuid` | PK/FK → `player_ideas.id` |
| `run_id` | `uuid` | FK → `game_runs.id` |
| `position` | `integer` | 1以上 |
| `queued_at` | `timestamptz` | NOT NULL |

`UNIQUE (run_id, position)`。削除・投稿時は行を削除する。これにより、`queued / published / deleted` の矛盾した状態を作らない。

### 5.4 `weekly_actions`

| カラム | 型 | 制約 |
|---|---|---|
| `id` | `uuid` | PK |
| `run_id` | `uuid` | FK → `game_runs.id` |
| `week_number` | `integer` | 1以上 |
| `action_rule_id` | `uuid` | FK → `action_rules.id` |
| `selected_at` | `timestamptz` | NOT NULL |
| `locked_at` | `timestamptz` | `advanceWeek` 確定後に設定 |

`UNIQUE (run_id, week_number)`。現在仕様に不要な汎用 `payload JSONB` は置かず、将来コラボ相手などが必要になった時点で型付き子テーブルを追加する。

### 5.5 `ability_point_grants` と `ability_allocations`

ポイント残高だけを上書きせず、付与元と使用先を追跡する。

`ability_point_grants`：

- `id`, `run_id`, `earned_week`, `available_from_week`
- `amount`
- `status`：`available / held / expired / consumed`
- `UNIQUE (run_id, earned_week)`

`ability_allocations`：

- `id`, `grant_id`, `ability_code`, `points`, `allocated_week`, `created_at`
- 使用済み量は `SUM(ability_allocations.points)` から算出し、重複する `spent_amount` 列は持たない
- 同一トランザクションで `run_abilities.value` と配分行を更新する

活動不能中の保持と復帰後の失効は、付与行の `status` で明示する。

### 5.6 `equipment_purchases`

購入時の価格と変更前後を履歴として保存する。

- `id`, `run_id`, `equipment_type_code`
- `from_tier_rule_id`（初回購入はNULL）
- `to_tier_rule_id`, `price_paid`, `purchased_week`, `created_at`

現在装備は `run_equipment`、購入時点の監査はこの表を参照する。

## 6. システム企画と週間履歴

### 6.1 `system_idea_cycles` と `system_idea_cycle_entries`

チャンネル別50件をシャッフルした一巡分の順序を、サイクル開始時に確定して保存する。

`system_idea_cycles`：

- `id`, `run_id`, `cycle_number`, `created_week`, `created_at`
- `UNIQUE (run_id, cycle_number)`

`system_idea_cycle_entries`：

- `id`, `cycle_id`, `system_idea_rule_id`, `position`
- `UNIQUE (cycle_id, system_idea_rule_id)`
- `UNIQUE (cycle_id, position)`
- `position`は1〜50

使用済みかどうかは`videos.system_idea_cycle_entry_id`の存在から導出し、重複する`used`列は持たない。50件を使い切った時だけ次サイクルを作成し、前サイクルの50番目と次サイクルの1番目が同じテンプレートになる順序は拒否する。

### 6.2 `advance_week_executions`

`advanceWeek`の冪等性と結果参照の起点。

| カラム | 型 | 制約・意味 |
|---|---|---|
| `idempotency_key` | `uuid` | PK、Server Actionが操作ごとに生成 |
| `run_id` | `uuid` | FK → `game_runs.id` |
| `attempted_week` | `integer` | 実行対象週 |
| `expected_state_version` | `integer` | 呼び出し時の版 |
| `outcome` | `text` | `week_committed / fatal_game_over` |
| `created_at` | `timestamptz` | NOT NULL |

同じキーの再送ではこの行に結び付く`week_results`または`game_terminations`から同じDTOを再構築して返す。技術的失敗時はトランザクションごとロールバックするため、未完了行を残さない。

### 6.3 `week_results`

週確定時の変更不能な集計スナップショット。

| カラム群 | 主なカラム |
|---|---|
| 識別 | `id`, `execution_id`, `run_id`, `week_number`, `weekly_action_id`, `posting_frequency_rule_id` |
| 再生数 | `views_before_event`, `final_views` |
| 登録者 | `subscribers_before`, `max_subscribers_during_week`, `subscribers_after` |
| 体力 | `energy_before`, `energy_after` |
| 所持金 | `cash_before`, `cash_after`, `ad_revenue` |
| 炎上 | `flame_count_after` |
| 終了状態 | `run_status_after`, `state_version_after`, `created_at` |

`execution_id`は`advance_week_executions.idempotency_key`への一意FKとする。`UNIQUE (run_id, week_number)`。差分列は保存せず、Viewで`after - before`を計算する。`max_subscribers_during_week`は同じ週の後続減少より前に解放条件へ到達した事実を保存する。ランダムイベント倍率は`occurred_events.event_rule_id`、炎上発生有無は炎上イベントの存在から導出する。活動不能週は`weekly_action_id`と`posting_frequency_rule_id`をNULLにできる。

### 6.4 `videos`

動画という事実と企画参照だけを持つ。

| カラム | 型 | 制約 |
|---|---|---|
| `id` | `uuid` | PK |
| `week_result_id` | `uuid` | FK → `week_results.id` |
| `sequence_number` | `smallint` | 週内順序 |
| `player_idea_id` | `uuid` | FK → `player_ideas.id`、NULL可 |
| `system_idea_cycle_entry_id` | `uuid` | FK → `system_idea_cycle_entries.id`、NULL可 |
| `title_snapshot` | `text` | 投稿時の表示名を固定 |

プレイヤー企画とシステム企画の参照は必ず片方だけ、`player_idea_id` は全動画を通して一意とする。

### 6.5 `video_calculations`

動画ごとの計算監査スナップショット。`video_id` をPK/FKとする1対1。

- `base_views`
- `subscriber_multiplier`
- `ability_multiplier`
- `idea_multiplier`
- `posting_frequency_multiplier`
- `channel_multiplier`
- `equipment_multiplier`
- `collaboration_multiplier`
- `views_before_event`, `event_multiplier`, `final_views`
- `conversion_rate`, `subscribers_gained`

倍率列は正規化不足ではなく、「その動画を確定した時点の計算根拠」という1つの事実の属性である。後日ルールが変わっても更新しない。

`event_multiplier`は週間イベント倍率のスナップショットであり、`final_views`は週間総再生数を比例配分した後の整数とする。配分は最大剰余法を使い、小数部分が同率なら`videos.sequence_number`の昇順を優先する。

### 6.6 `occurred_events`

| カラム | 型 | 意味 |
|---|---|---|
| `id` | `uuid` | PK |
| `week_result_id` | `uuid` | FK → `week_results.id` |
| `event_definition_code` | `text` | FK → `event_definitions.code` |
| `event_rule_id` | `uuid` | ランダムイベントならFK、炎上等はNULL可 |
| `sequence_number` | `smallint` | 処理順 |
| `display_metadata` | `jsonb` | 表示文差し込みなど非正本情報だけ |
| `created_at` | `timestamptz` | NOT NULL |

登録者減少、体力減少、再生数倍率などの正本は型付き結果テーブルに置き、`display_metadata` にゲーム状態を保存しない。

### 6.7 `game_terminations`

人生が終了した理由を1ゲーム1行で保存する。

| カラム | 型 | 意味 |
|---|---|---|
| `id` | `uuid` | PK |
| `run_id` | `uuid` | UNIQUE、FK → `game_runs.id` |
| `execution_id` | `uuid` | 致死週ならUNIQUE、FK → `advance_week_executions.idempotency_key`。中断はNULL可 |
| `week_result_id` | `uuid` | 期限切れならUNIQUE、FK → `week_results.id`。死亡・BAN・中断はNULL |
| `reason` | `text` | `death / flame_ban / deadline / abandoned` |
| `occurred_week` | `integer` | 終了が成立した週 |
| `calculated_energy` | `smallint` | 死亡判定値。該当しなければNULL |
| `calculated_flame_count` | `smallint` | BAN判定値。該当しなければNULL |
| `created_at` | `timestamptz` | NOT NULL |

死亡・BANでは通常の`week_results`を作らず、現在値、企画、行動効果、解放、ポイントを更新しない。終了理由の監査に必要な終端値だけをこの表へ保存し、`game_runs.status`を`game_over`へ変更する。期限切れは通常の`week_results`を確定したうえで紐付ける。中断は最後の確定状態を維持する。

## 7. バージョン付きルール

すべての数値ルールは `rule_sets` 配下へ置く。ゲーム開始後は `game_runs.rule_set_id` を変更しない。

### 7.1 静的カタログ

名称や識別コードだけを持ち、バランス値を持たない。

- `channel_types(code, name)`
- `ability_definitions(code, name, display_order)`
- `equipment_types(code, name, display_order)`
- `action_definitions(code, name, description)`
- `feature_definitions(code, name)`
- `event_categories(code, name)`
- `event_definitions(code, category_code, name)`

拡張可能な種類をPostgreSQL Enumへ固定しない。コードはFKで保証し、廃止は `enabled` やルールセット側で扱う。

### 7.2 `rule_sets`

`id`, `version`, `status`, `published_at`, `created_at` を持つ。`status` は `draft / active / retired`。公開後のルール行は更新せず、変更時は新しいルールセットを作る。

### 7.3 型付きルールテーブル

| テーブル | 主な列 |
|---|---|
| `global_rules` | 基礎再生数範囲、体力上限、活動不能週の回復量、企画作成上限、ストック上限、炎上ペナルティ、BAN回数、広告単価、システム企画倍率・転換率 |
| `channel_rules` | チャンネル種類、再生数倍率、週間炎上確率 |
| `channel_ability_weights` | チャンネルルール、能力コード、重み。現仕様では各チャンネル2能力を0.5ずつ |
| `posting_frequency_rules` | 投稿本数、再生数倍率、体力消費、付与能力ポイント |
| `idea_score_band_rules` | 最低点、最高点、再生数倍率、転換率 |
| `equipment_tier_rules` | 機材種類、ランク、価格、再生数補正 |
| `action_rules` | 行動、必要機能、クールダウン、固定所持金差分、体力差分、動画倍率 |
| `sponsorship_reward_rules` | 企業案件の登録者数下限・上限と報酬額 |
| `feature_rules` | 機能、解放登録者数、利用開始までの週数、永続解放か |
| `goal_rules` | ステージ、目標登録者、期間、最終目標か |
| `event_category_rules` | 良い・悪いカテゴリの週間発生確率。各5% |
| `event_rules` | イベント、カテゴリ内抽選重み、週間再生数倍率、固定金額差分、固定登録者差分、登録者倍率 |
| `health_risk_rules` | 体力下限・上限、発生確率、活動不能期間の最小・最大週数 |
| `system_idea_templates` | 管理コード、変更不能なタイトル・短い説明、チャンネル種類、有効状態 |
| `rule_set_system_ideas` | ルールセットと使用可能な企画テンプレートの対応、有効状態 |

`sponsorship_reward_rules`は登録者数範囲の重複を排他制約で禁止する。`health_risk_rules`は50〜100、30〜49、10〜29、1〜9の確定帯を隙間なく持ち、期間は発症時に両端を含む均等分布で抽選する。イベントの良い・悪いカテゴリ内は各イベントの`selection_weight=1`で均等抽選する。

### 7.4 自動生成企画コンテンツとDB投入

企画作成・レビュー時の正本は `data/system-ideas/*.json` とし、王道系50件、炎上系50件、アイドル系50件の合計150件を収録する。特化系50件は専門ジャンル分類の決定後に別セッションで追加し、最終的に4チャンネル合計200件とする。

JSONとDBの対応は次のとおり。

| JSON | DB |
|---|---|
| `ideas[].code` | `system_idea_templates.code` |
| ファイル直下の `channelTypeCode` | `system_idea_templates.channel_type_code` |
| `ideas[].title` | `system_idea_templates.title` |
| `ideas[].description` | `system_idea_templates.description` |
| `ideas[].enabled` | `system_idea_templates.enabled` |

JSONはDB実装前の中間成果物であり、ゲーム実行時は参照しない。後続セッションでJSONを入力とする冪等なseed処理を実装し、`system_idea_templates` へ投入したうえで、`rule_set_system_ideas(rule_set_id, system_idea_template_id, enabled)` によりルールセットと関連付ける。ゲーム実行時はRepositoryを通してDBだけを参照する。

現行の6.1節と `DATABASE_ERD.svg` はサイクル項目を `system_idea_rule_id` と表記しているが、7.3節で定義している対応テーブル名は `rule_set_system_ideas` であり、参照先の命名が一致していない。DB実装時は `rule_set_system_idea_id` など、`rule_set_system_ideas` へのFKであることが明確な名称へ統一する。今回のJSON作成ではDBスキーマを変更しない。

## 8. View / DTO

画面都合の横持ちは、書き込みテーブルではなく次のViewで提供する。

| View | 用途 |
|---|---|
| `current_game_view` | `run_state`、能力、機材、現在目標、解放機能を1行へ集約 |
| `idea_stock_view` | キュー順、企画タイトル、AI評価の内部状態を結合 |
| `week_history_view` | before/afterから差分を計算し、行動名・イベント名を結合 |
| `video_result_view` | 動画と計算スナップショットを結合 |

Supabaseで公開するViewは `security_invoker = true` を使用し、基底テーブルのRLSを迂回させない。AI評価点をプレイヤーへ返す公開Viewには含めない。

## 9. 不変条件とDB制約

- すべての金額・再生数・登録者数・ポイントは整数型を使う。
- 倍率と確率は `numeric` を使い、`double precision` の誤差を避ける。
- `run_state.state_version` は更新ごとに1増やす。
- `week_results`、`videos`、`video_calculations`、`occurred_events` は確定後UPDATE禁止。
- 1匿名ユーザーにつき`playing / stage_cleared`のゲームは最大1件。
- 1ゲームにつき進行中目標は最大1件。
- 1週につきメイン行動と週結果は各最大1件。
- 企画キュー位置はゲーム内で一意。
- プレイヤー企画は最大1本の動画でしか消費できない。
- システム企画は1サイクル50件の位置とテンプレートがそれぞれ一意で、動画から最大1回だけ参照できる。
- 能力配分履歴は取り消し・更新せず、振り直しを許可しない。
- 機能解放行は一度作成したら削除せず、同じ週の後続登録者減少でも維持する。
- 致死週は`week_results`と通常の子履歴を作らず、`game_terminations`だけを作る。
- ルールセット公開後は、その配下のルール行を更新・削除しない。
- バージョン付きルールへのFKが、ゲームの `rule_set_id` と一致することを制約トリガーで保証する。
- `run_equipment.equipment_type_code` と参照先ティアルールの機材種類は、複合FKまたは制約トリガーで一致させる。
- `idea_score_band_rules` は点数範囲の重複を排他制約で禁止し、0〜100を隙間なく覆うことを公開時検証で保証する。
- `channel_ability_weights` はチャンネルごとの重み合計が1になることを公開時検証で保証する。
- `event_rules`の倍率・登録者倍率は0以上、金額・固定登録者差分は仕様上の符号と範囲をCHECKで保証する。
- `event_category_rules`は良い5%・悪い5%、`event_rules.selection_weight`は各カテゴリ内で正の整数とする。
- `health_risk_rules`と`sponsorship_reward_rules`の範囲重複を排他制約で禁止する。

## 10. トランザクション境界

ゲーム計算はNext.jsサーバー上の副作用のないTypeScript関数で行う。保存はServer専用PostgreSQL関数`commit_advance_week`へ集約し、Supabase Edge Functionsは初期版で使用しない。

1. `idempotency_key`を先に検索し、存在すれば保存済み結果を返す
2. `run_state`を`SELECT ... FOR UPDATE`し、所有者、処理対象週、`state_version`を検証
3. `weekly_actions`をロック
4. `advance_week_executions`をINSERT
5. 通常確定なら企画キュー消費、システム企画サイクル、`week_results`、動画、イベント、目標、解放、健康状態、能力ポイント、現在値を保存
6. 死亡・BANなら通常結果を保存せず、`game_terminations`と`game_runs.status`だけを保存
7. 期限切れなら通常週を保存した後、`game_terminations`と`game_runs.status`を保存
8. すべて成功した場合だけCOMMIT。例外時は実行行を含めてROLLBACK

`UNIQUE (run_id, week_number)`、`advance_week_executions.idempotency_key`、`run_state.state_version`の3層で、同じ週の二重確定と再送を防ぐ。乱数はNext.jsサーバーで生成し、生の乱数値・シード・カーソルは保存しない。DBには基礎再生数、確定企画順、発生イベント、炎上、活動不能期間などの結果だけを保存する。

OpenAI呼び出しは長時間トランザクションを避けるため、DBトランザクション外で実行する。企画作成は、事前確認→AI評価→短いトランザクション内で週間上限と在庫上限を再確認→企画・評価・キューを確定する。フォールバック60点でも同じ経路を通す。並行リクエストでAI呼び出しが重複しても、最終再確認によってDB上限は破られない。

## 11. RLS

- 匿名ユーザーもSupabase上では`auth.users.id`と認証済みセッションを持つ。未認証の`anon`ロールへゲームデータを公開しない。
- `game_runs.user_id = auth.uid()` を所有権の起点にする。
- 子テーブルは `EXISTS` で所有する `game_runs` まで辿る。
- AI評価点はServer専用Queryだけで取得し、クライアント向けSELECTポリシーから除外する。
- 静的カタログと公開済みルールは読み取り専用。
- `draft` ルールセットは管理者だけが読める。
- 複雑な週進行は直接テーブル更新を許可せず、Server Action → Use Case →Server専用DB関数の経路に集約する。
- `commit_advance_week`は`PUBLIC`、`anon`、`authenticated`から`EXECUTE`を剥奪し、Server Actionだけが保持するサーバー資格情報から呼ぶ。関数内でもセッションから得た実行主体IDと`game_runs.user_id`の一致を検証する。

## 12. 主なインデックス

```sql
game_runs(user_id, status)
game_runs(user_id) UNIQUE WHERE status IN ('playing', 'stage_cleared')
run_goals(run_id) WHERE status = 'active'
run_conditions(run_id, unavailable_through_week) WHERE recovered_at IS NULL
player_ideas(run_id, created_week)
idea_queue_entries(run_id, position) UNIQUE
weekly_actions(run_id, week_number) UNIQUE
ability_point_grants(run_id, status)
advance_week_executions(idempotency_key) UNIQUE
week_results(run_id, week_number) UNIQUE
videos(week_result_id, sequence_number) UNIQUE
videos(player_idea_id) UNIQUE WHERE player_idea_id IS NOT NULL
videos(system_idea_cycle_entry_id) UNIQUE WHERE system_idea_cycle_entry_id IS NOT NULL
system_idea_cycles(run_id, cycle_number) UNIQUE
system_idea_cycle_entries(cycle_id, position) UNIQUE
occurred_events(week_result_id, sequence_number)
game_terminations(run_id) UNIQUE
```

## 13. 実装順

1. 静的カタログと `rule_sets` 配下の型付きルール
2. `game_runs`、`run_state`、能力・機材・目標・解放テーブル
3. 企画、キュー、週次行動、システム企画サイクル
4. 週・動画・イベント・ゲーム終了履歴、冪等実行管理
5. 制約、トリガー、RLS
6. 読み取りView
7. Repositoryとユースケース

企業案件、健康状態、匿名セーブは確定仕様として初期マイグレーションへ含める。コラボ相手、治療、アカウント連携、チュートリアルは将来仕様が決まるまで追加しない。

## 14. 運用上の保守ルール

- スキーマ変更はSupabase Dashboardの手作業ではなく、番号付きSQLマイグレーションだけで行う。
- ルール初期値は冪等なseed SQLにし、アプリコードへ同じ数値を重複記述しない。
- 公開済みルールへのUPDATE・DELETEはDBトリガーで拒否する。
- ルール・履歴へのFKは原則 `ON DELETE RESTRICT`。ゲーム人生を削除する場合も即時物理削除せず、削除要求日時を記録して専用処理で扱う。
- 構成要素だけの子行（企画評価、キュー行など）に限り、親の物理削除が許される環境では `ON DELETE CASCADE` を検討する。
- DB生成型をTypeScriptへ出力し、手書きのDB Row型を重複管理しない。画面DTOはDB型と分離する。
- 主要制約、RLS、ルールセット公開検証、`advanceWeek` の二重実行をDBテストで確認する。
- Repositoryはテーブル単位ではなく、`GameRunRepository`、`IdeaStockRepository`、`WeekResultRepository` のような集約単位にする。
