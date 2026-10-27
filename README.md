# ゆーちゅーばーになろう！（仮）

YouTuberとしてチャンネルを成長させるブラウザシミュレーションゲームの開発プロジェクトです。現在は開発環境だけを用意しており、ゲーム機能はまだ実装していません。

## 使用技術

- **Next.js 16 / App Router**: 画面、サーバー処理、ルーティング
- **TypeScript**: 型安全な実装
- **Tailwind CSS 4**: UIのスタイリング
- **Supabase** (`@supabase/supabase-js`, `@supabase/ssr`): 将来のデータ保存と認証
- **OpenAI JavaScript SDK**: 将来の動画企画評価（サーバー側だけで利用）
- **Cloudflare Workers + vinext**: サーバー処理を含むCloudflareデプロイ
- **Vitest**: Node.js環境でのバックエンド単体・Applicationテスト
- **ESLint**: コード品質チェック
- **npm / Git**: パッケージ管理、バージョン管理

Cloudflareは、サーバー側でOpenAI APIを呼び出す将来要件があるため、静的サイト向けのPagesではなくWorkersを採用しています。2026年10月時点でCloudflareが新規Next.jsアプリに推奨する `vinext` を併設しています。`vinext` はまだベータ版でNext.js APIをVite上に再実装するため、通常のNext.jsビルドとCloudflare向けビルドの両方を継続的に確認してください。

## 必要な環境

- Node.js 22.23.2（LTS）
- npm 10系
- Git

このプロジェクトには `.nvmrc` があります。nvmを使う場合は次のコマンドでNode.jsを合わせられます。

```bash
nvm install
nvm use
```

現在のCloudflare CLI依存関係は奇数版Node.jsをサポートしていません。Node.js 25ではなく、上記のLTSを使用してください。

## セットアップ

```bash
npm install
cp .env.example .env.local
```

`.env.local` に実際の値を設定します。接続情報が空でもトップページの起動とビルドはできます。

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_key
OPENAI_API_KEY=sk-your-openai-api-key
```

- `NEXT_PUBLIC_` が付く値はブラウザに公開されます。SupabaseのProject URLとpublishable key以外の秘密情報を入れないでください。
- Supabaseのsecret keyや旧 `service_role` keyを公開変数に設定しないでください。
- `OPENAI_API_KEY` に `NEXT_PUBLIC_` を付けないでください。
- `.env.local` や `.dev.vars` はGit対象外です。実値を `.env.example` に書かないでください。

## ローカル開発

Next.js標準の開発サーバーを起動します。

```bash
npm run dev
```

ブラウザで <http://localhost:3000> を開きます。

Cloudflare Workersに近い環境を使う場合は、別途vinextの開発サーバーを起動します。

```bash
npm run cf:dev
```

## 品質チェックとビルド

```bash
npm run system-ideas:validate
npm run lint
npm test
npm run typecheck
npm run build
```

開発中にバックエンドテストをwatchする場合:

```bash
npm run test:watch
```

テスト種別ごとのコマンド、バックエンド各層の責務、依存方向、Server専用境界は [`docs/BACKEND_STRUCTURE.md`](docs/BACKEND_STRUCTURE.md) を参照してください。

通常ビルドは、制限された実行環境でも安定して検証できるようNext.jsのWebpackビルドを使用します。ローカル開発はNext.js標準のTurbopackです。

Cloudflare Workers向けのビルドとローカルプレビューは次のとおりです。

```bash
npm run cf:build
npm run cf:preview
```

Cloudflare Bindingの型を再生成する場合:

```bash
npm run cf-typegen
```

## Cloudflare Workersへのデプロイ

このリポジトリでは `cloudflare.config.ts` と `vite.config.ts` を使用します。実際のデプロイはまだ行っていません。

1. Cloudflareアカウントを用意します。
2. `npx wrangler login` またはCloudflare CLIが案内する認証を完了します。
3. Cloudflare DashboardまたはCLIで `OPENAI_API_KEY` を秘密情報として登録します。
4. SupabaseのURLとpublishable keyもWorkersの環境変数に登録します。
5. `npm run deploy` を実行します。
6. デプロイ後、トップページと将来追加するサーバールートを実環境で確認します。

無料枠で必ず運用できるとは限りません。Workers Freeにはリクエスト数、CPU時間、メモリ、サブリクエスト等の制限があります。SSRやAI連携を追加した後は実測し、必要なら有料プランを検討してください。

## Supabase接続の残作業

`lib/supabase/client.ts` と `lib/supabase/server.ts` に、ブラウザ用・サーバー用クライアント生成処理を分離して用意しています。未設定時は、これらを実際に呼び出したときだけ明確なエラーになります。

今後の作業:

1. Supabaseプロジェクトを作成する。
2. Project URLとpublishable keyを `.env.local` に設定する。
3. 必要なテーブル、Row Level Security、ポリシー、マイグレーションを設計する。
4. ログインを実装する段階で、公式ガイドに従い `proxy.ts` を追加してセッション更新を構成する。
5. ブラウザから操作する全テーブルでRLSが有効か確認する。

## OpenAI API接続の残作業

`lib/openai/server.ts` に、サーバー専用環境変数からクライアントを生成する関数だけを用意しています。API呼び出しやプロンプトは実装していません。

今後の作業:

1. `.env.local` とCloudflareの秘密情報に `OPENAI_API_KEY` を設定する。
2. サーバー側のRoute HandlerまたはServer Actionからだけクライアントを呼び出す。
3. 入力検証、タイムアウト、レート制限、エラー処理、利用量監視を追加する。
4. キーがクライアントバンドルやログに含まれないことを確認する。

## ディレクトリ構成

```text
app/                    App Routerの画面・レイアウト
backend/                Domain / Application / Infrastructure / Queries / Actions（実装時に追加）
lib/supabase/           Supabaseのクライアント生成処理
lib/openai/             OpenAIのサーバー用クライアント生成処理
tests/                  単体・Application・DB・結合テスト
docs/BACKEND_STRUCTURE.md
                        バックエンド配置・依存・Server専用境界の規約
public/                 将来の静的素材（必要になった時点で追加）
cloudflare.config.ts    Cloudflare Worker設定
vite.config.ts          vinext / Cloudflare向けVite設定
.env.example            環境変数の名前とダミー値
```

## 今回実装していないもの

登録者数・再生数・所持金・体力、週進行、動画企画の作成やAI評価、能力値、ランダムイベント、炎上・病気・ケガ、コラボ・企業案件、ドット絵、週間履歴、セーブ・ロード、ログイン、データベーステーブル、実際の外部API接続は未実装です。

## 参考にした公式ドキュメント

- [Next.js: Installation](https://nextjs.org/docs/app/getting-started/installation)
- [Cloudflare Workers: Next.js](https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/)
- [Cloudflare Workers: Limits](https://developers.cloudflare.com/workers/platform/limits/)
- [Supabase: Creating a client for SSR](https://supabase.com/docs/guides/auth/server-side/creating-a-client)
- [Supabase: API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [OpenAI API: Libraries](https://platform.openai.com/docs/libraries/javascript)

