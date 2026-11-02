# Supabaseローカル開発

このプロジェクトのDBスキーマの正本は `supabase/migrations/` の番号付きSQLです。Supabase DashboardやローカルStudioでの手作業を正本にせず、変更は必ずマイグレーションとしてレビュー可能にします。この手順はローカルDB専用であり、Supabaseのリモートプロジェクトへ接続しません。

## 必要なツール

- `.nvmrc` に記載したNode.js 22.23.2とnpm 10
- Docker Desktopなど、起動済みのDocker互換ランタイム
- 冪等性テストでローカルPostgreSQLへ接続する `psql`
- プロジェクトのdevDependencyとして固定したSupabase CLI 2.122.0

依存関係は `npm ci` で再現します。Supabase CLIはグローバルインストールせず、npm scriptsまたは `npx supabase` から実行してください。

## 日常のローカル操作

```bash
npm run db:start
npm run db:status
npm run db:lint
npm run db:test
npm run db:stop
```

`db:start` はローカルサービスを起動し、未適用マイグレーションとseedを適用します。`db:status` はこのローカルスタックの状態と接続情報を表示します。`db:stop` はこのプロジェクトのコンテナだけを停止し、データを保持します。

空のローカルDBから同じ状態を再現するには、起動後に次を実行します。

```bash
npm run db:reset
```

`db:reset` は `--local` を明示し、ローカルDBを再作成して全マイグレーションとseedを順番に適用します。ローカルデータは消えるため、対象がこのリポジトリの `project_id = "youtuber-game"` であることを `npm run db:status` で確認してください。

## マイグレーションとseed

新しいスキーマ変更は、短いsnake_case名で番号付きファイルを作ります。

```bash
npx supabase migration new add_example_table
npm run db:reset
```

ファイル名はCLIが生成する `<UTCの14桁タイムスタンプ>_<snake_caseの説明>.sql` を使用します。既に共有済みのマイグレーションを書き換えず、追加のマイグレーションで変更してください。

- マイグレーション: `supabase/migrations/*.sql`
- seed: `supabase/seed.sql` と `supabase/seeds/*.sql`
- pgTAP SQL: `supabase/tests/database/*.sql`

seedはマイグレーション完了後、`supabase/config.toml` の `db.seed.sql_paths` に記載した次の順で実行されます。

1. `supabase/seed.sql`: 静的マスタ、初期ルールセット、数値ルール
2. `supabase/seeds/010_system_ideas.sql`: 650件の企画と初期ルールセットとの関連
3. `supabase/seeds/020_publish_initial_rule_set.sql`: seed内容の完全一致と公開条件を検証し、1.0.0をactive化

企画内容の正本は `data/system-ideas` のJSONです。生成SQLを直接編集せず、JSON変更時は次を実行します。

```bash
npm run system-ideas:docs
npm run system-ideas:validate
npm run system-ideas:seed:generate
npm run system-ideas:seed:check
```

生成SQLはGit管理するため、CIやDB resetでNode.jsからJSONを読む必要はありません。ゲーム実行時もJSONを参照せず、`system_idea_templates` と `rule_set_system_ideas` だけを使用します。DDLはseedではなくマイグレーションへ置きます。

初回seedではdraftの1.0.0へデータを投入し、公開前検証後にactive化します。activeな1.0.0へ再実行した場合は公開済み行を更新せず、seedとDBの完全一致を検証します。不一致やretired状態では自動修正せず失敗します。ルール変更時は公開済み1.0.0を上書きせず、新しいバージョンを作成してください。

同じローカルDBへseed一式を2回実行し、件数・UUID・内容・`published_at`が変わらないことを確認するには次を実行します。このコマンドは最初にローカルDBをresetするため、保存中のローカルデータは削除されます。

```bash
npm run db:seed:idempotency
```

## lintとDBテスト

```bash
npm run db:lint
npm run db:test
```

`db:lint` はローカルDBの `public` スキーマを `plpgsql_check` で検査し、warning以上で失敗します。`db:test` はSupabase CLIが `supabase/tests/database/*.sql` をpgTAPで直接実行します。

`tests/db/**/*.test.ts` は将来、VitestとSupabaseクライアントからローカルDBへ接続するTypeScript結合テストを置く場所です。現在の `npm run test:db` はその領域だけを実行します。SQLレベルの制約・RLS・DB関数はpgTAPへ、アプリケーションからの接続経路はTypeScriptへ置き、同じ確認を二重管理しません。

## リモートDBを使わない安全ルール

- 通常の開発では `supabase link`、`supabase db push`、`supabase db reset --linked` を実行しません。
- ローカル操作はnpm scriptsを使い、DBコマンドでは `--local` を明示します。
- `supabase/.temp/`、`supabase/.branches/`、`.env.local`、`.dev.vars` はコミットしません。
- 実際のURL、publishable key、secret key、旧 `service_role` keyはリポジトリへ保存しません。
- 後続チケットはゲームテーブル・RLS・DB関数を番号付きマイグレーション、静的データを冪等seed、SQL不変条件をpgTAPへ追加します。
