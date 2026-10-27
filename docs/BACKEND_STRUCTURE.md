# バックエンド構成規約

この文書は、バックエンド実装の配置、依存方向、Server専用境界、テスト分類を定める。ゲームルールの正本は `docs/ゆーちゅーばーになろう（仮）_ゲーム仕様書.md`、DB設計の正本は `DATABASE_DESIGN.md` とする。

## ディレクトリ構成

後続チケットでは、実装対象ができた時点で次のディレクトリを作る。空ディレクトリを維持するためのファイルは追加しない。

```text
app/                              App Routerの画面とRoute Handlers
backend/
  domain/                         純粋なドメイン型・値オブジェクト・計算・エラー
  application/                    ユースケース・Port・Input / Result
  infrastructure/                 Supabase・OpenAI・環境変数・Mapper・Port実装
  queries/                        読み取り専用Query / DALと画面DTO
  actions/                        Server Actionsと公開入力境界
lib/                              既存の接続用コード。後続作業で段階的に各層へ整理
tests/
  unit/                           Domain中心の純粋な単体テスト
  application/                    ユースケースとFake Portのテスト
  db/                             PostgreSQL制約・関数・RLSのテスト
  integration/                    Action / Queryから外部境界までの結合テスト
```

`app/` と `lib/` は `src/` へ移動しない。Next.jsのルートは `app/` に保ち、フレームワークから独立したバックエンドコードはプロジェクト直下の `backend/` に置く。

## 依存方向

基本方向は次のとおりとする。

```text
Client Components ──> actions ──> application ──> domain
Server Components ──> queries ──> infrastructure ──> DB

infrastructure ──implements──> applicationのPort
infrastructure ──────────────> domain
```

- `domain` は他のバックエンド層へ依存しない。
- `application` は `domain` と同じ層に定義したPortだけへ依存する。
- `infrastructure` は `application` のPortを実装し、必要に応じて `domain` へDB Rowを変換する。
- `queries` は読み取り専用のDALであり、認可後に画面専用DTOを返す。DB Rowを公開しない。
- `actions` は公開入力を検証し、認証済み実行コンテキストと依存実装を用意してユースケースを呼ぶ。
- 層をまたぐimportは `@/backend/...` の絶対パスを使い、ESLintの境界検査を必ず通す。同じ層の近接モジュールだけ相対importを許可する。
- Server Componentsは表示データを `queries` から取得する。Client Componentsは `queries`、`infrastructure`、DB型をimportしない。
- 将来のRoute Handlersは `actions` の関数を再利用せず、同じ `application` ユースケースを呼ぶ。

## 各層の責務とimport規則

### Domain

配置例：`backend/domain/game/`、`backend/domain/shared/`

含めるもの：

- DBや画面に依存しないエンティティと型
- ゲームルールを計算する副作用のない関数
- 値オブジェクト
- ドメインエラー

importしてよいもの：

- 同じ `backend/domain/` 内のモジュール
- 実行時依存を持たないTypeScriptの型

importまたは直接利用してはいけないもの：

- Next.js、React、`server-only`
- Supabase SDK、OpenAI SDK
- Cookie、`process.env`
- `Date.now()`、`new Date()`、`Math.random()`などの実時刻・実乱数
- Application、Infrastructure、Queries、Actions

必要な時刻や乱数は、呼び出し側が値として渡す。DomainはブラウザでもNode.jsでも同じ入力から同じ結果を返せる状態を保つ。

### Application

配置例：`backend/application/use-cases/start-game.ts`、`backend/application/ports/clock.ts`

含めるもの：

- 1操作を完了させるユースケース
- Repository、`Clock`、`RandomSource`、外部サービスのPort（インターフェース）
- ユースケースのInput / Result
- 認証済み主体を表す `UseCaseContext`

importしてよいもの：

- Domain
- Application内のPortと共通型

importしてはいけないもの：

- Reactコンポーネント、画面レイアウト、Next.js API
- Supabase SDK、OpenAI SDK、`server-only`
- Infrastructure、Queries、Actions
- SupabaseのDB Row型やView Row型
- Cookie、環境変数、実時刻、実乱数

公開Inputには `userId` を含めない。登録者数、体力、所持金、能力、炎上回数などの現在値も含めず、Repositoryから取得する。

### Infrastructure

配置例：`backend/infrastructure/supabase/`、`backend/infrastructure/openai/`

含めるもの：

- Supabase Repositoryの実装
- OpenAI Adapter
- 外部サービス接続、サーバー専用環境変数
- DB生成型と、DB RowからDomainへのMapper
- 実時計・実乱数などApplication Portの実装

すべての実行モジュールの先頭で `import "server-only"` を使用する。DomainやApplicationの型だけを再exportする公開バレルは作らない。秘密情報へアクセスするのはこの層に限定する。

DB Row型は生成物としてInfrastructure内に閉じ込める。Domain型や画面DTOの代用にせず、Mapperで明示的に変換する。

importしてよいもの：

- Domain型とApplicationのPort
- `server-only`、Supabase・OpenAIなど担当Adapterに必要なSDK
- サーバー専用の接続・環境設定モジュール

importしてはいけないもの：

- ReactコンポーネントとClient Component
- ActionsとQueries
- `app/` の画面・レイアウト

### Queries

配置例：`backend/queries/get-current-game.ts`

含めるもの：

- 画面表示用DTOを返す読み取り専用処理
- PostgreSQL ViewまたはQuery / DALによる結合
- 読み取り時の認証・認可

QueryもDBとセッションへ触れるServer専用コードなので `import "server-only"` を付ける。更新処理、ゲーム計算、DB Rowの返却を行わない。Client Componentへ渡す値は、必要最小限かつシリアライズ可能なDTOにする。

importしてよいもの：

- `server-only`、認証・DB接続、Infrastructure内のDB生成型
- DTOの組み立てに必要なDomainの読み取り型

importしてはいけないもの：

- ReactコンポーネントとClient Component
- Actionsと更新系ユースケース
- OpenAI Adapter、ゲーム計算関数

### Actions

配置例：`backend/actions/start-game-action.ts`

含めるもの：

- `"use server"` と `import "server-only"` を持つServer Actions
- 匿名セッションの確立・確認
- 公開Inputの検証
- ユースケース呼び出し
- 安定したエラーコードへの変換
- 成功後の再検証

ゲーム計算やテーブル更新を直接書かない。ブラウザから渡された `userId` や現在値を信用せず、認証セッションから `UseCaseContext.actorUserId` を作る。

importしてよいもの：

- `server-only`、Next.jsのServer Action・再検証API
- 公開入力の検証器、Applicationユースケース
- 認証と依存注入に必要なInfrastructureの構築関数

importしてはいけないもの：

- ReactコンポーネントとClient Component
- SupabaseのDB Row型やテーブル更新関数
- Domainのゲーム計算関数を直接実行するモジュール

## Server専用境界

- DomainとApplicationは `server-only` に依存させず、純粋なロジックとして単体テスト可能にする。
- Infrastructure、Queries、Actionsには `import "server-only"` を付け、Client Componentからのimportをビルド時に失敗させる。
- `"use client"` ファイルから `backend/infrastructure`、`backend/queries`、`backend/actions`、`lib/*/server` をimportしない。
- Server Actionsと将来のRoute Handlersは同じApplicationユースケースを呼ぶ。
- `advanceWeek` の複数テーブル保存はServer専用DB関数 `commit_advance_week` に集約する。
- 実OpenAI API、実時刻、実乱数、開発者の `.env.local` へ単体テストを依存させない。
- `vitest.config.ts` は `envDir: false` とし、アプリ用 `.env*` を自動ロードしない。DB・結合テストの資格情報は、ローカルのテストDBまたはCIからテスト専用値として明示的に渡す。

既存の `lib/openai/server.ts` と `lib/supabase/server.ts` もServer専用である。後続チケットでAdapterやRepositoryを実装するときに、振る舞いを変えず `backend/infrastructure/` へ段階的に整理する。

## テストの配置と役割

| 種類 | 配置 | 対象 | 外部依存 |
|---|---|---|---|
| 単体 | `tests/unit/**/*.test.ts` | Domainの型・値・純粋関数 | DB、ネットワーク、実時刻、実乱数を使わない |
| Application | `tests/application/**/*.test.ts` | ユースケースの進行、認可、Port呼び出し | Fake Repository、Fake Clock、固定RandomSourceを注入 |
| DB | `tests/db/**/*.test.ts` | migration、制約、RLS、DB関数 | 毎回初期化できるローカルテストDBだけを使用 |
| 結合 | `tests/integration/**/*.test.ts` | Action / Queryと実Adapterの接続 | テスト専用サービスを使用し、実OpenAIには接続しない |

単体テストとApplicationテストは並列実行可能な独立したテストにする。DBテストは各ケースが残した状態に依存させない。結合テストでは外部境界を必要最小限にし、OpenAI AdapterはFakeへ差し替える。

## テストコマンド

```bash
npm test                  # CI向け。単体 + Applicationを1回実行
npm run test:watch        # 開発向け。単体 + Applicationをwatch
npm run test:unit         # 単体テストだけ
npm run test:application  # Applicationテストだけ
npm run test:db           # DBテストだけ（BE-002以降で追加）
npm run test:integration  # 結合テストだけ（対象実装時に追加）
```

未実装カテゴリの個別コマンドには `--passWithNoTests` を付けている。各カテゴリに最初のテストが追加された時点で外し、テストの欠落をCIで検知できるようにする。`npm test` は `--passWithNoTests` を使わず、常に少なくとも1件のテスト実行を要求する。

## 新しいユースケースの追加例

`startGame` を追加する場合は次の順で配置する。

1. Domain型・不変条件を `backend/domain/game/` に置く。
2. `StartGameInput`、`StartGameResult`、必要なRepository Portを `backend/application/` に置く。
3. ユースケースを `backend/application/use-cases/start-game.ts` に置く。
4. DB Row MapperとRepository実装を `backend/infrastructure/supabase/` に置く。
5. Server Actionを `backend/actions/start-game-action.ts` に置く。
6. 単体テストを `tests/unit/`、Fake Portを使うユースケーステストを `tests/application/` に置く。
7. DB制約は `tests/db/`、Actionまで含む経路は `tests/integration/` に置く。

ActionsやRoute Handlersから別々の業務ロジックを作らず、手順3の同じユースケースへ集約する。

## 後続チケットの配置

| チケット群 | 主な追加先 |
|---|---|
| BE-002〜BE-012 | 将来の `supabase/`、`backend/infrastructure/supabase/`、`backend/queries/`、`tests/db/` |
| BE-013 | `backend/application/ports/`、`backend/infrastructure/` |
| BE-014〜BE-017 | `backend/application/use-cases/`、`backend/actions/`、`backend/queries/` |
| BE-018 | `backend/application/ports/`、`backend/infrastructure/openai/` |
| BE-019〜BE-024 | `backend/application/use-cases/`、`tests/application/` |
| BE-025〜BE-028 | `backend/domain/`、`tests/unit/` |
| BE-029〜BE-031 | DB関数、`backend/application/`、`backend/queries/`、DB・Applicationテスト |
| BE-032〜BE-035 | `backend/actions/`、`tests/integration/`、品質確認設定 |

BE-001では `supabase/`、DBマイグレーション、Repository、Query実装、Server Action実装、ゲーム計算を先行作成しない。

## 禁止事項

- Domainへフレームワーク、SDK、Cookie、環境変数、実時刻、実乱数を持ち込まない。
- DB Row、Domain型、画面DTOを同じ型として使い回さない。
- ApplicationからDBテーブルを直接操作しない。
- Queriesに更新処理を持たせない。
- Actionsへゲーム計算やSQLを実装しない。
- 公開Inputに所有者IDやサーバー側の現在値を含めない。
- 実OpenAI APIや本番DBを自動テストから呼ばない。
- 確定していないゲームルールをテスト都合で仮実装しない。
