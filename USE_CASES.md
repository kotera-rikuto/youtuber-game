# 『YouTuberになろう！（仮）』ユースケース関数一覧

> ステータス：非UI実装着手版  
> 更新日：2026年10月27日  
> 参照仕様：`docs/ゆーちゅーばーになろう（仮）_ゲーム仕様書.md`

## 1. ユースケース関数の位置づけ

ユースケース関数は、プレイヤーが行う1つの操作をバックエンドで最後まで成立させる関数とする。

```text
Client Component
  → Server Action（匿名セッション確認・入力検証）
  → Use Case（処理全体の進行・認可）
  → Game Engine / Repository / OpenAI Adapter
  → Supabase
```

Server Action、画面表示用Query、ゲーム内部の計算関数はユースケース関数へ含めない。

初回の「始める」操作では、Server Action境界でSupabase匿名認証セッションを自動作成する。以後はCookieだけからセッションを復元し、`auth.users.id`を実行主体として使用する。`userId`は公開Inputへ含めず、次の検証済み実行コンテキストとしてユースケースへ渡す。

```ts
type UseCaseContext = {
  actorUserId: string;
};
```

## 2. 初期版のユースケース一覧

| # | 関数名 | プレイヤーの操作 | 主な責務 | 状態 |
|---:|---|---|---|---|
| 1 | `startGame` | 新しいゲームを開始する | チャンネル名・種類・特化時の専門分野と初期値でゲーム人生を作成する | 必須 |
| 2 | `abandonGame` | 現在の人生を中断する | 進行中ゲームを終了し、新しい人生を開始可能にする | 必須 |
| 3 | `renameChannel` | チャンネル名を変更する | チャンネル種類は変えず、名前だけ更新する | 必須 |
| 4 | `setPostingFrequency` | 週の投稿本数を変更する | 週1・3・7本の設定を保存する | 必須 |
| 5 | `createIdea` | 自由記述企画をストックする | 週3件・在庫30件を検証し、AI評価とともに保存する | 必須 |
| 6 | `deleteIdea` | 投稿前企画を削除する | 削除後も週間追加枠を戻さず論理削除する | 必須 |
| 7 | `reorderIdeaStock` | 企画の投稿順を並べ替える | 投稿待ち企画のキュー順を保存する | 必須 |
| 8 | `allocateAbilityPoints` | 能力ポイントを割り振る | 使用可能ポイントを6能力へ不可逆に反映する | 必須 |
| 9 | `purchaseEquipment` | 機材を購入・強化する | 価格と所持金を検証し、上位ランクへ置換する | 必須 |
| 10 | `selectWeeklyMainAction` | その週のメイン行動を選ぶ | 4行動から必ず1つ選び、解放・クールダウンを検証する | 必須 |
| 11 | `advanceWeek` | 「次週に進む」を押す | 行動、自動投稿、イベント、目標判定を一括確定する | 必須 |
| 12 | `advanceStage` | 「次のステージへ進む」を押す | 現在値を引き継ぎ、次の156週間を開始する | 必須 |

ゲーム側企画を追加する公開操作はない。不足分の選出は `advanceWeek` 内部の処理とするため、`generateIdeas` はユースケースにしない。

## 3. 各ユースケースの責務

### 3.1 `startGame`

```ts
type SpecialtyCode =
  | "baseball"
  | "soccer"
  | "gaming"
  | "pc_gadgets"
  | "science"
  | "history_culture"
  | "occult"
  | "nature"
  | "food_culture"
  | "outdoor_survival";

type NonSpecializedPostingStyle = "mainstream" | "controversial" | "idol";

type StartGameInput =
  | {
      channelName: string;
      postingStyle: "specialized";
      specialtyCode: SpecialtyCode;
    }
  | {
      channelName: string;
      postingStyle: NonSpecializedPostingStyle;
      specialtyCode?: never;
    };

type StartGameResult = {
  runId: string;
};
```

画面は`postingStyle === "specialized"`のときだけ専門分野の選択欄を表示し、未選択では開始操作を送信できない。他の3種類へ切り替えた場合は、クライアント側の専門分野選択値を破棄する。ただし、正しさは画面だけに依存せず、Server Actionのスキーマ検証、ユースケース、DB制約でも保証する。

処理内容：

1. Server Actionが保証した匿名セッションの`UseCaseContext.actorUserId`を受け取る。
2. 同じ匿名ユーザーに`playing`または`stage_cleared`のゲームがないことを確認する。
3. チャンネル名と、アクティブなルールセットで選択可能なチャンネル種類を検証する。
4. 特化系なら`specialtyCode`が必須で、アクティブな`rule_set_specialties`に含まれる10分野のいずれかであることを確認する。特化系以外で値が送られた場合も拒否する。
5. `game_runs`へ変更不能なチャンネル種類と専門分野を保存する。専門分野は特化系だけ非NULLとする。
6. 登録者0、所持金100,000円、体力100、6能力各10、能力ポイント0、機材なし、企画空、週1本、処理対象週1を設定する。
7. ステージ1「第156週までに登録者10万人」を設定する。
8. ルールバージョンと状態バージョンを保存する。生の乱数や乱数シードは保存しない。

終了済みゲームは上書きしない。年齢は初期版の入力・ゲーム計算・DBに含めない。専門分野は企画プールだけを決定し、能力参照・チャンネル倍率・炎上確率は特化系の共通ルールを使う。

### 3.2 `abandonGame`

所有者と進行状態を検証し、`game_runs.status`を`abandoned`へ変更する。`game_terminations`へ中断理由と発生週を保存し、過去の状態・履歴は削除しない。中断後は同じ匿名ユーザーが新しい`game_runs`を作成できる。

### 3.3 `renameChannel`

進行中のゲームのチャンネル名だけを変更する。チャンネル種類と特化系の専門分野は変更できない。

### 3.4 `setPostingFrequency`

```ts
type SetPostingFrequencyInput = {
  runId: string;
  postingFrequency: 1 | 3 | 7;
  expectedVersion: number;
};
```

所有者・活動状態・`run_state.state_version` を確認し、同じルールセットの `posting_frequency_rules` を参照して `run_state.posting_frequency_rule_id` を保存する。設定は次に変更するまで維持され、`advanceWeek` 実行時の値をその週へ適用する。

### 3.5 `createIdea`

```ts
type CreateIdeaInput = {
  runId: string;
  title: string;
  description?: string;
  expectedVersion: number;
};

type CreateIdeaResult = {
  ideaId: string;
  evaluationStatus: "completed" | "fallback";
};
```

処理内容：

1. 所有者、活動状態、状態バージョンを確認する。
2. タイトルが1〜100文字であることを確認する。
3. `created_week` を基準に、その週の作成数が3件未満か確認する。削除済み企画も作成数に含める。
4. 未投稿・未削除のストックが30件未満か確認する。
5. OpenAIへ新規性・魅力度・チャンネル適合度の評価を依頼し、0〜100の整数へ検証・変換する。
6. API失敗時は60点のフォールバック評価を使用する。
7. `player_ideas` と `idea_evaluations` を同時に保存し、`idea_queue_entries` の末尾へ追加する。

評価は作成時に1回だけ行い、再評価・編集はしない。評価点はプレイヤーへ表示しない。

### 3.6 `deleteIdea`

未投稿のプレイヤー企画だけを論理削除する。`player_ideas.deleted_at` を設定し、対応する `idea_queue_entries` を削除する。企画原本は物理削除しないため、その週の作成枠は回復しない。削除後は残ったキューの順番を詰める。

### 3.7 `reorderIdeaStock`

```ts
type ReorderIdeaStockInput = {
  runId: string;
  orderedIdeaIds: string[];
  expectedVersion: number;
};
```

未投稿・未削除の全企画が重複や欠落なく含まれることを確認し、`idea_queue_entries.position` を一括更新する。

### 3.8 `allocateAbilityPoints`

```ts
type AllocateAbilityPointsInput = {
  runId: string;
  planning: number;
  talking: number;
  expertise: number;
  editing: number;
  visual: number;
  filming: number;
  expectedVersion: number;
};
```

6項目が0以上の整数で、合計が使用可能な `ability_point_grants` の残量以下、反映後の各能力が100以下であることを検証する。割り振りは `ability_allocations` に記録し、`run_abilities` の対応行を更新する。能力強化はメイン行動と体力を消費しない。活動不能中は使用できない。

能力ポイントは正常に投稿した週の終了時に、週1本=3、週3本=7、週7本=15を翌週用として付与する。累積せず、通常週の次週進行時に未使用分を失効させて新しい獲得分へ置換する。活動不能中は既存ポイントを保持し、復帰後最初の通常週の終了時に同じ置換規則を適用する。一度確定した配分は振り直せない。

### 3.9 `purchaseEquipment`

```ts
type EquipmentType = "camera" | "microphone" | "editing_pc";
type EquipmentLevel = "beginner" | "intermediate" | "advanced";

type PurchaseEquipmentInput = {
  runId: string;
  equipmentType: EquipmentType;
  level: EquipmentLevel;
  expectedVersion: number;
};
```

価格は次の固定マスタを参照する。

| 機材 | 初級 | 中級 | 上級 |
|---|---:|---:|---:|
| カメラ | 30,000円 | 150,000円 | 500,000円 |
| マイク | 5,000円 | 30,000円 | 100,000円 |
| 編集PC | 50,000円 | 200,000円 | 500,000円 |

所持金不足や同等・下位ランクの購入を拒否し、購入時は `run_equipment` の同種行を上位の `equipment_tier_rule_id` へ置換し、`equipment_purchases` に支払価格と変更前後を保存する。購入はメイン行動と体力を消費しない。機材故障イベントでも所有ランクは失われない。

### 3.10 `selectWeeklyMainAction`

```ts
type WeeklyMainAction =
  | "part_time_job"
  | "rest"
  | "collaboration"
  | "sponsorship";

type SelectWeeklyMainActionInput = {
  runId: string;
  action: WeeklyMainAction;
  expectedVersion: number;
};
```

1週間につき `weekly_actions` に必ず1つだけ保存し、再選択時は同じ週の行を置換する。`advanceWeek` 確定後は `locked_at` を設定して変更不能にする。活動不能中は選択できない。コラボ・企業案件は `run_feature_unlocks` と `action_rules` のクールダウンを検証する。

確定効果：

- アルバイト：所持金+10,000円、体力-10
- 休憩：体力+50（投稿消費より先、最大100）
- コラボ：登録者50,000人で永続解放、体力-10、費用なし、その週の全動画へ1.5倍、実施週を含む2週間のクールダウン
- 企業案件：登録者100,000人で永続解放、体力-5、費用なし、実施週を含む4週間のクールダウン。週開始時の登録者数に対応する`sponsorship_reward_rules`の報酬を所持金へ加算

コラボ・企業案件は第N週に実施した場合、それぞれ第N+2週、第N+4週から再選択できる。初期版のコラボは相手を選択・保存しない。

### 3.11 `advanceWeek`

```ts
type AdvanceWeekInput = {
  runId: string;
  expectedVersion: number;
  idempotencyKey: string;
};

type CommittedWeekResult = {
  outcome: "week_committed";
  completedWeek: number;
  nextWeek: number;
  publishedVideos: number;
  totalViews: number;
  subscriberDelta: number;
  adRevenue: number;
  energyDelta: number;
  abilityPointsAwarded: number;
  events: GameEventDTO[];
  gameStatus: "playing" | "stage_cleared" | "cleared" | "game_over";
  nextStateVersion: number;
};

type FatalGameOverResult = {
  outcome: "fatal_game_over";
  attemptedWeek: number;
  reason: "death" | "flame_ban";
  gameStatus: "game_over";
};

type AdvanceWeekResult = CommittedWeekResult | FatalGameOverResult;
```

通常週の処理順：

1. `idempotencyKey`で確定済み実行を先に検索し、同じリクエストの再送なら保存済み結果を返す。
2. 所有者、実行可能状態、処理対象週、`expectedVersion` を確認する。
3. 現在状態、ステージ、企画、メイン行動、ルールを取得する。
4. その週のメイン行動が1つ選ばれていることを確認し、効果を適用する。休憩は先に回復し、企業案件報酬は週開始時登録者数から決定する。
5. 投稿本数分のプレイヤー企画をキュー先頭から選び、不足分を確定済みのシステム企画サイクル順から補う。特化系は`game_runs.specialty_code`に一致する50件、それ以外はチャンネル種類に一致する50件だけを使い、サイクルがなければ対象50件をシャッフルして作る。
6. 動画ごとに0〜100,000の基礎再生数を生成し、登録者・能力・企画・投稿頻度・チャンネル・機材・コラボの7倍率を掛けて切り捨てる。
7. 炎上とは独立して週間ランダムイベントを判定する。良い5%・悪い5%・なし90%とし、カテゴリ内3種類は均等抽選する。
8. 再生数イベント後の正式週間総再生数を切り捨て、元の再生数比率で動画へ比例配分する。端数は小数部分が大きい順、同率なら投稿順で配分する。
9. 補正後動画別再生数と企画別転換率から動画ごとに登録者増加を切り捨てて合計し、広告解放済みなら`floor(補正後週間総再生数 × 0.2円)`を計算する。ランダムイベントの直接的な登録者・所持金効果も適用する。
10. 動画増加後など、週内のいずれかの時点で登録者3,000・50,000・100,000へ初到達した機能を記録する。同じ週の後続減少で取り消さない。広告、コラボ、企業案件はいずれも翌週から利用可能にする。
11. 投稿頻度に応じた週間体力消費（3・8・25）を反映する。
12. その週に1回だけ炎上を判定する。週間確率は炎上系5.0%、その他3種類0.1%で、投稿本数には依存しない。発生時は再生数を変えず、登録者を`floor(炎上前登録者数 × 0.95)`へ更新し、体力を20減少、累積炎上回数を1増加させる。
13. 炎上回数が3回ならBAN、そうでなく体力が0以下なら死亡とする。致死週は通常結果を破棄し、`game_terminations`とゲーム状態だけを専用トランザクションで保存する。両方成立した場合はBANを主理由とする。
14. 致死でなければ残り体力に応じて体調不良を判定し、期間を範囲内の整数から均等抽選する。発生週は確定し、翌週から活動不能にする。
15. 正常に投稿できた週の翌週用能力ポイント（3・7・15）を付与し、未使用分は仕様どおり置換する。
16. ステージ目標と期限を判定する。最終週の達成も成功とし、未達ならその週を通常確定した後で期限切れゲームオーバーにする。
17. PostgreSQLの`commit_advance_week`関数が`run_state`をロックして`state_version`を再検証し、企画、週結果、動画、イベント、目標、解放、体調不良、能力ポイント、現在値を1トランザクションで保存する。

活動不能週は「次週に進む」だけを受け付け、体力を10回復して処理対象週を1つ進める。メイン行動、自動投稿、週間ランダムイベント、炎上、健康状態の再抽選、能力ポイントの獲得・使用は行わない。既存の未使用ポイントは保持する。行動・投稿頻度がNULLの`week_results`を作成して経過週と体力変化を記録し、その週もステージ期限を判定する。期限最終週なら回復週を確定した後、未達時に期限切れゲームオーバーとする。

予期しない処理失敗では週を進めず、トランザクション全体をロールバックする。致死ゲームオーバーは失敗ではなく、通常週結果を適用せず終了記録だけを確定する。

### 3.12 `advanceStage`

`stage_cleared`状態でだけ実行できる。現在値、企画ストック、能力、機材、累計週数をすべて維持する。第N週に達成した場合、次ステージの最初の処理対象週を第N+1週、期限を第N+156週に設定する。ステージ5達成後は実行できない。

## 4. `advanceWeek` が呼ぶ内部関数

以下は画面から直接呼ばないゲームエンジン関数である。

| 関数名 | 責務 |
|---|---|
| `applyWeeklyMainAction` | 1つのメイン行動の効果を適用する |
| `selectIdeasFromStock` | キュー先頭から投稿本数分のプレイヤー企画を選ぶ |
| `resolveSystemIdeaPool` | ゲーム人生のチャンネル種類を参照し、特化系なら固定済み専門分野まで一致する有効な50件を取得する |
| `createSystemIdeaCycle` | `resolveSystemIdeaPool`が返した50件をシャッフルし、直前サイクル末尾との連続重複を避けた順序を作る |
| `selectSystemIdeasWithoutRepeat` | 確定済みサイクルの未使用先頭から不足数を選ぶ |
| `calculateSubscriberMultiplier` | 現在登録者数から倍率を計算する |
| `calculateAbilityMultiplier` | チャンネル種類に対応する2能力の平均から倍率を計算する |
| `calculateEquipmentMultiplier` | 3機材の補正を合算し最大1.45倍にする |
| `simulateVideos` | 動画ごとに基礎再生数と7倍率からイベント前再生数を計算する |
| `rollWeeklyRandomEvent` | 炎上とは独立に、良い5%・悪い5%・なし90%を判定し、発生カテゴリ内を均等抽選する |
| `applyWeeklyViewEvent` | 週間総再生数へのイベント倍率を適用する |
| `allocateAdjustedViewsToVideos` | 比例配分と最大剰余法で動画別結果へ反映し、週間合計と一致させる |
| `calculateSubscriberChanges` | 補正後動画別再生数と転換率から登録者増加を計算する |
| `calculateAdRevenue` | 解放済みの場合に補正後再生数×0.2円を切り捨てる |
| `applyPostingEnergyCost` | 投稿頻度別の週間体力消費を適用する |
| `rollFlameEvent` | 週1回、炎上系5.0%・その他0.1%で判定し、登録者を `floor(現在値×0.95)`、体力を-20にする |
| `rollHealthEvent` | 残り体力帯の確率で体調不良を判定し、範囲内の整数から期間を均等抽選する |
| `replaceAbilityPointsForNextWeek` | 未使用ポイントの失効と翌週分の付与を処理する |
| `checkFeatureUnlocks` | 週内到達最大値から広告・コラボ・企業案件の永続解放と翌週利用開始を記録する |
| `checkGameOver` | 死亡・BAN・ステージ期限切れを判定する |
| `checkStageGoal` | 現ステージ目標達成と最終クリアを判定する |

乱数はNext.jsサーバー上の差し替え可能な`RandomSource`インターフェースから取得する。生の乱数値、シード、カーソルはDBへ保存せず、基礎再生数、選出企画、発生イベント、炎上有無、体調不良期間など、ゲーム結果に使用した確定値だけを型付き履歴へ保存する。テストでは固定値を返す実装へ差し替える。

### 4.1 自動生成企画のデータソース

- 王道系50件、炎上系50件、アイドル系50件の合計150件を `data/system-ideas/*.json` に作成済み
- 特化系10分野の企画データは今回の作業対象に含めず、既存の `resolveSystemIdeaPool` と専門分野設計を変更しない
- JSONは企画作成・レビュー時の正本であり、ゲーム実行時には読み込まない
- JSONから `system_idea_templates` と `rule_set_system_ideas` へ投入する冪等なseed処理は後続セッションで実装する
- `resolveSystemIdeaPool`、`createSystemIdeaCycle`、`selectSystemIdeasWithoutRepeat` は、ゲームのルールセット、チャンネル種類、必要な場合は専門分野に対応する有効な企画をRepository経由でDBから取得する
- サイクル作成時は対象プールからちょうど50件取得できることを検証し、不足・重複があれば週進行を確定しない

## 5. 画面表示用Query（ユースケース関数ではない）

| 関数名 | 返すDTO |
|---|---|
| `getGameStartOptionsDTO` | アクティブなルールセットの4チャンネル種類と、特化系で選択可能な10専門分野。専門分野コード・表示名・表示順を返す |
| `getCurrentGameDTO` | `current_game_view` からチャンネル、現在値、6能力、機材、目標、解放状態 |
| `getIdeaStockDTO` | `idea_stock_view` から未投稿企画、キュー順、今週の作成済み件数 |
| `getWeeklyActionOptionsDTO` | 4行動の解放状態、クールダウン、選択中行動 |
| `getCurrentGoalDTO` | 現在ステージ、目標、開始週、期限、進捗 |
| `getWeekHistoryDTO` | `week_history_view` から週間結果と算出済み差分 |
| `getWeekResultDTO` | `video_result_view` を含む特定週の行動、7倍率、再生数、収益、イベント詳細 |
| `getFinalResultDTO` | 最終登録者、累計再生数、所持金、経過年数、炎上回数など |

これらはServer ComponentsからQuery / DALを通して呼び出す。

## 6. 初期版に含めない拡張候補

| 候補 | 現在の扱い |
|---|---|
| `completeTutorialStep` | チュートリアルの対象操作・終了条件待ち |
| コラボ相手選択 | 初期版では相手を選択・保存しない |
| 体調不良の個別名称・効果 | 初期版では共通の`activity_unavailable`として扱う |
| 体調不良の治療 | 初期版では治療・期間短縮を設けない |
| アカウント連携・端末移行 | 初期版では匿名Cookieによる同一ブラウザ再開だけを扱う |

コラボは独立ユースケースではなく、週間メイン行動として扱う。スタッフ機能と動画制作費は初期版に含めない。

## 7. 実装上の共通ルール

- 更新系ユースケースは公開Inputとは別に`UseCaseContext.actorUserId`を受け取り、対象ゲームの所有権を認可する。
- ブラウザから渡された登録者数、体力、所持金、能力値などの現在値は信用せず、DBから取得し直す。
- `advanceWeek`は`idempotencyKey`を先に確認し、同一リクエストの再送には同じ結果を返す。
- `expectedVersion`とDBの`state_version`を比較し、二重実行・古い画面からの更新を防ぐ。`UNIQUE (run_id, week_number)`も併用する。
- ゲーム計算は可能な限り副作用のないTypeScript関数として実装する。
- OpenAIの出力はスキーマ検証し、評価点だけをゲーム計算へ渡す。再生数などをAIに決めさせない。
- `advanceWeek`の計算はTypeScriptで行い、保存はServer専用のPostgreSQL関数`commit_advance_week`へ集約する。この関数は`anon`・`authenticated`から直接実行できないよう権限を剥奪する。
- `commit_advance_week`は行ロック・所有者・状態バージョンを再検証し、複数更新を全成功または全失敗となるよう原子的に保存する。
- 初期版ではSupabase Edge Functionsを使用しない。
- Server Actionと将来のRoute Handlerは同じユースケース関数を呼び出す。
- 確定済み週結果には、ルールバージョンと計算に使った倍率・スナップショットを残し、後から説明・再現できるようにする。
- `game_runs` は識別情報、`run_state` は現在値、`week_results` 以下は確定履歴として責務を混ぜない。
- 能力、機材、解放機能、企画キューを横持ち列やJSONBにせず、型付きの子テーブルで扱う。
- バランス値は公開後変更不能な `rule_sets` 配下の型付きルールから取得し、巨大な設定JSONBを作らない。
- 特化系の専門分野は`startGame`でだけ設定し、以後の更新ユースケースでは変更しない。システム企画取得時は必ずサーバー側の`game_runs.specialty_code`を使用し、クライアントから企画プールを指定させない。

## 8. 共通エラーコード

Server Actionは例外文言へ依存せず、ユースケースの判定結果を次の安定したコードへ変換する。

| コード | 意味 |
|---|---|
| `UNAUTHENTICATED` | 匿名セッションを確立・検証できない |
| `RUN_NOT_FOUND` | 対象ゲームが存在しない |
| `FORBIDDEN` | 対象ゲームの所有者ではない |
| `RUN_NOT_PLAYABLE` | クリア・ゲームオーバー・中断済みなど実行不能な状態 |
| `ACTIVITY_UNAVAILABLE` | 活動不能中に禁止操作を行った |
| `STALE_STATE` | `expectedVersion`が現在値と一致しない |
| `WEEK_ALREADY_COMMITTED` | 同じ週が別リクエストですでに確定済み |
| `WEEKLY_ACTION_REQUIRED` | 通常週のメイン行動が選択されていない |
| `FEATURE_LOCKED` | コラボ・企業案件などが未解放 |
| `ACTION_COOLDOWN` | 行動がクールダウン中 |
| `INSUFFICIENT_FUNDS` | 機材購入に必要な所持金がない |
| `IDEA_WEEKLY_LIMIT` | その週の企画作成3件を使い切った |
| `IDEA_STOCK_FULL` | 未投稿企画が30件に達している |
| `SPECIALTY_REQUIRED` | 特化系なのに専門分野が未選択 |
| `SPECIALTY_NOT_ALLOWED` | 特化系以外で専門分野が指定された、または現在のルールセットで選択できない専門分野が指定された |
| `VALIDATION_ERROR` | 文字数、列挙値、配分値などの入力不正 |

同じ`idempotencyKey`の再送はエラーではなく、最初に確定した`AdvanceWeekResult`を返す。
