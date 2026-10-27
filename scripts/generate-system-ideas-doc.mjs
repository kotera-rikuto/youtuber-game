import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dataDirectory = path.join(repoRoot, "data", "system-ideas");
const outputPath = path.join(repoRoot, "docs", "SYSTEM_IDEAS.md");

export const systemIdeaFiles = [
  ["mainstream", "王道系", "mainstream.json"],
  ["controversial", "炎上系", "controversial.json"],
  ["idol", "アイドル系", "idol.json"],
];

export async function loadSystemIdeaCollections() {
  return Promise.all(
    systemIdeaFiles.map(async ([code, label, filename]) => {
      const source = await readFile(path.join(dataDirectory, filename), "utf8");
      return { code, label, filename, data: JSON.parse(source) };
    }),
  );
}

function escapeTableCell(value) {
  return String(value).replaceAll("|", "\\|").replaceAll("\n", "<br>");
}

function renderIdeaTable(collection) {
  const showCategory = collection.code === "controversial";
  const header = showCategory
    ? "| code | title | description | enabled | 内部レビュー分類 |\n|---|---|---|:---:|---|"
    : "| code | title | description | enabled |\n|---|---|---|:---:|";
  const rows = collection.data.ideas.map((idea) => {
    const columns = [
      `\`${idea.code}\``,
      escapeTableCell(idea.title),
      escapeTableCell(idea.description),
      idea.enabled ? "true" : "false",
    ];
    if (showCategory) {
      columns.push(`\`staged_nuisance_style\``);
    }
    return `| ${columns.join(" | ")} |`;
  });
  return [header, ...rows].join("\n");
}

export function renderSystemIdeasDoc(collections) {
  const sections = collections
    .map(
      (collection) =>
        `## ${collection.label}50件\n\n${renderIdeaTable(collection)}`,
    )
    .join("\n\n");

  return `# 自動生成企画一覧

> この文書は \`data/system-ideas/*.json\` から生成するレビュー用一覧です。タイトル・説明文を直接編集せず、JSONを更新してから \`npm run system-ideas:docs\` を実行してください。

## 現在の収録状況

- 王道系（\`mainstream\`）：50件、完成
- 炎上系（\`controversial\`）：50件、完成
- アイドル系（\`idol\`）：50件、完成
- 特化系（\`specialized\`）：今回未作成。既存仕様の10専門分野各50件は別セッションで追加する
- 現在合計：150件
- 既存仕様上の最終予定：王道系・炎上系・アイドル系150件と特化系500件の合計650件

## データ項目

各チャンネルファイルは \`schemaVersion\`、\`channelTypeCode\`、\`ideas\` を持ちます。各企画は次の項目だけを持ちます。

| JSON項目 | 用途 |
|---|---|
| \`code\` | 変更されにくいASCII識別子 |
| \`title\` | 1〜100文字の企画タイトル |
| \`description\` | 35〜80文字の短い企画説明 |
| \`enabled\` | 企画を利用可能にする真偽値 |

チャンネルコードはファイル直下で一度だけ保持し、各企画へ重複保存しません。UUID、AI評価点、倍率、登録者転換率、サムネイル、使用済み状態、シャッフル順、ゲームID、ルールセットUUID、企画固有補正は保存しません。

## JSONとDBの関係

JSONは企画作成・レビュー時の正本ですが、ゲーム実行時のデータソースではありません。後続セッションでJSONを読み込む冪等なseed処理を実装し、Supabase PostgreSQLへ投入します。ゲーム実行時はRepositoryを通してDBだけを参照します。

| JSON | DB |
|---|---|
| \`ideas[].code\` | \`system_idea_templates.code\` |
| \`channelTypeCode\` | \`system_idea_templates.channel_type_code\` |
| \`ideas[].title\` | \`system_idea_templates.title\` |
| \`ideas[].description\` | \`system_idea_templates.description\` |
| \`ideas[].enabled\` | \`system_idea_templates.enabled\` |

\`rule_set_system_ideas\` は、後続seedで \`rule_set_id\`、\`system_idea_template_id\`、有効状態を関連付けます。現行DB資料の \`system_idea_cycle_entries.system_idea_rule_id\` は参照先の名称が曖昧なため、DB実装時に \`rule_set_system_ideas\` を参照するFK名へ統一します。これは今回のJSON形式を変更しません。

## 全体の作成方針

- 実際の動画タイトルに近い、長期間使えるクリック志向の表現にする
- タイトルは目安8〜40文字、上限100文字とする
- 説明文は一覧表示と管理レビューの両方で内容が分かる35〜80文字とする
- 完全一致タイトル、同一チャンネル内の意味的重複、単語だけを替えた水増しを避ける
- 同じ題材でも、チャンネル固有の視聴体験が明確に異なる場合は許容する
- 実在する個人、企業、商品、作品や一時的な流行へ依存しない
- 王道系は理解しやすさとクリックしたくなる強さを両立する
- アイドル系は美容、生活、自己管理を中心にし、特定の性別を前提にしない

## 炎上系の表現基準

炎上系は、批評、商品レビュー、問題提起、危険性の検証ではなく、人や周囲へ迷惑をかける過激な動画を中心にします。無断侵入風、営業妨害風、所有物の破壊、騒音、強引ないたずらなど、非常識さがタイトルだけで伝わる内容にします。

爆破や破壊を含む大げさな企画表現は使用できますが、人を殺す内容、実在する個人・企業への攻撃、現実で危険行為や犯罪を再現するための具体的手順は含めません。各説明文で、撮影用セット、架空施設、合意済み出演者、小道具などを使ったゲーム内の演出であることを明らかにします。

## 炎上系の内部レビュー分類

利用可能な分類語彙は \`strong_opinion\`、\`harsh_review\`、\`taboo\`、\`extreme_challenge\`、\`exposure_style\`、\`social_experiment\`、\`controversial_comparison\`、\`staged_nuisance_style\` です。

最新の確定方針により、今回の炎上系50件はすべて迷惑系動画として作成したため、全件を \`staged_nuisance_style\` に分類します。この分類はレビュー専用であり、JSONやDBのゲームデータには追加しません。

## 重複防止と検証

\`npm run system-ideas:validate\` でJSON Schema、件数、連番コード、コードとタイトルの全体一意性、文字数、許可フィールド、特化系0件、Markdownとの一致を検証します。同一チャンネル内のタイトル類似度も機械的に検査し、最終的な意味重複は人間が一覧で確認します。

## 将来650件へ統合する方法

特化系は既存仕様の10専門分野ごとに50件を別セッションで作成します。専門分野コードを保持できるようJSON Schemaと生成・検証スクリプトをそのセッションで拡張し、レビュー後のseedで既存3チャンネルと同じテーブルへ投入します。今回の150件を作り直す必要はありません。

## 後続seed実装で必要な作業

1. JSONを入力とする冪等なseed処理を作成する
2. \`system_idea_templates.code\` を自然キーとしてinsertまたは安全なupsertを行う
3. 対応する \`channel_types.code\` の存在を検証する
4. 対象ルールセットと \`rule_set_system_ideas\` を関連付ける
5. チャンネルごとに有効な企画が50件であることをルールセット公開時に検証する
6. ゲーム実行時にJSONを読み込まず、RepositoryからDBを取得する
7. 一巡50件のシャッフルとサイクル境界の連続重複回避をテストする

${sections}
`;
}

async function main() {
  const collections = await loadSystemIdeaCollections();
  await writeFile(outputPath, renderSystemIdeasDoc(collections), "utf8");
  console.log(`Generated ${path.relative(repoRoot, outputPath)} from ${collections.length} JSON files.`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
