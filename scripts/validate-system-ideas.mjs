import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadSystemIdeaCollections,
  renderSystemIdeasDoc,
  systemIdeaFiles,
} from "./generate-system-ideas-doc.mjs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dataDirectory = path.join(repoRoot, "data", "system-ideas");
const schemaPath = path.join(dataDirectory, "system-idea.schema.json");
const markdownPath = path.join(repoRoot, "docs", "SYSTEM_IDEAS.md");

function lengthOf(value) {
  return Array.from(value).length;
}

function validateAgainstSchema(value, schema, location, errors) {
  if (Object.hasOwn(schema, "const") && value !== schema.const) {
    errors.push(`${location}: must equal ${JSON.stringify(schema.const)}`);
  }
  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${location}: must be one of ${schema.enum.join(", ")}`);
  }

  if (schema.type === "object") {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      errors.push(`${location}: must be an object`);
      return;
    }
    for (const requiredKey of schema.required ?? []) {
      if (!Object.hasOwn(value, requiredKey)) {
        errors.push(`${location}: missing required property ${requiredKey}`);
      }
    }
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!Object.hasOwn(schema.properties ?? {}, key)) {
          errors.push(`${location}: unexpected property ${key}`);
        }
      }
    }
    for (const [key, childSchema] of Object.entries(schema.properties ?? {})) {
      if (Object.hasOwn(value, key)) {
        validateAgainstSchema(value[key], childSchema, `${location}.${key}`, errors);
      }
    }
    return;
  }

  if (schema.type === "array") {
    if (!Array.isArray(value)) {
      errors.push(`${location}: must be an array`);
      return;
    }
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${location}: must contain at least ${schema.minItems} items`);
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      errors.push(`${location}: must contain at most ${schema.maxItems} items`);
    }
    value.forEach((item, index) =>
      validateAgainstSchema(item, schema.items, `${location}[${index}]`, errors),
    );
    return;
  }

  if (schema.type === "string") {
    if (typeof value !== "string") {
      errors.push(`${location}: must be a string`);
      return;
    }
    const size = lengthOf(value);
    if (schema.minLength !== undefined && size < schema.minLength) {
      errors.push(`${location}: must contain at least ${schema.minLength} characters (found ${size})`);
    }
    if (schema.maxLength !== undefined && size > schema.maxLength) {
      errors.push(`${location}: must contain at most ${schema.maxLength} characters (found ${size})`);
    }
    if (schema.pattern && !new RegExp(schema.pattern, "u").test(value)) {
      errors.push(`${location}: does not match ${schema.pattern}`);
    }
    return;
  }

  if (schema.type === "boolean" && typeof value !== "boolean") {
    errors.push(`${location}: must be a boolean`);
  }
  if (schema.type === "integer" && !Number.isInteger(value)) {
    errors.push(`${location}: must be an integer`);
  }
}

function normalizeTitle(value) {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[【】「」『』（）()！？!?、。・\s]/gu, "")
    .replace(/[0-9]+/gu, "#");
}

function bigrams(value) {
  const characters = Array.from(value);
  if (characters.length < 2) return new Set(characters);
  return new Set(characters.slice(0, -1).map((character, index) => character + characters[index + 1]));
}

function jaccard(left, right) {
  const a = bigrams(normalizeTitle(left));
  const b = bigrams(normalizeTitle(right));
  const intersection = [...a].filter((item) => b.has(item)).length;
  const union = new Set([...a, ...b]).size;
  return union === 0 ? 1 : intersection / union;
}

async function main() {
  const errors = [];
  const schema = JSON.parse(await readFile(schemaPath, "utf8"));
  const collections = await loadSystemIdeaCollections();
  const expectedFiles = new Set(systemIdeaFiles.map(([, , filename]) => filename));
  const dataFiles = (await readdir(dataDirectory)).filter(
    (filename) => filename.endsWith(".json") && filename !== "system-idea.schema.json",
  );

  for (const filename of dataFiles) {
    if (!expectedFiles.has(filename)) {
      errors.push(`Unexpected channel data file: ${filename}`);
    }
  }

  const allIdeas = [];
  for (const collection of collections) {
    validateAgainstSchema(collection.data, schema, collection.filename, errors);
    if (collection.data.channelTypeCode !== collection.code) {
      errors.push(`${collection.filename}: channelTypeCode must be ${collection.code}`);
    }
    if (collection.data.ideas.length !== 50) {
      errors.push(`${collection.filename}: expected exactly 50 ideas`);
    }
    collection.data.ideas.forEach((idea, index) => {
      const expectedCode = `${collection.code}_${String(index + 1).padStart(3, "0")}`;
      if (idea.code !== expectedCode) {
        errors.push(`${collection.filename}: expected code ${expectedCode}, found ${idea.code}`);
      }
      if (idea.title !== idea.title.trim() || idea.description !== idea.description.trim()) {
        errors.push(`${idea.code}: title and description must not have surrounding whitespace`);
      }
      allIdeas.push({ ...idea, channelTypeCode: collection.code });
    });

    for (let left = 0; left < collection.data.ideas.length; left += 1) {
      for (let right = left + 1; right < collection.data.ideas.length; right += 1) {
        const score = jaccard(
          collection.data.ideas[left].title,
          collection.data.ideas[right].title,
        );
        if (score >= 0.82) {
          errors.push(
            `${collection.filename}: titles may be semantically duplicated (${score.toFixed(2)}): "${collection.data.ideas[left].title}" / "${collection.data.ideas[right].title}"`,
          );
        }
      }
    }
  }

  if (allIdeas.length !== 150) {
    errors.push(`Expected 150 total ideas, found ${allIdeas.length}`);
  }
  if (allIdeas.some((idea) => idea.channelTypeCode === "specialized")) {
    errors.push("specialized ideas must not be included in this delivery");
  }

  for (const field of ["code", "title"]) {
    const seen = new Map();
    for (const idea of allIdeas) {
      const value = idea[field];
      if (seen.has(value)) {
        errors.push(`Duplicate ${field}: ${value} (${seen.get(value)} and ${idea.code})`);
      } else {
        seen.set(value, idea.code);
      }
    }
  }

  const forbiddenFields = new Set([
    "aiScore",
    "evaluationScore",
    "viewMultiplier",
    "conversionRate",
    "thumbnail",
    "used",
    "shuffleOrder",
    "runId",
    "ruleSetId",
    "abilityAdjustment",
    "flameProbability",
    "minimumViews",
  ]);
  for (const idea of allIdeas) {
    for (const field of Object.keys(idea)) {
      if (forbiddenFields.has(field)) {
        errors.push(`${idea.code}: forbidden field ${field}`);
      }
    }
  }

  const controversial = allIdeas.filter(
    (idea) => idea.channelTypeCode === "controversial",
  );
  const stagedContextPattern = /(撮影|架空|貸切|出演者|小道具|セット|模型|複製品|空箱|停止した車両)/u;
  for (const idea of controversial) {
    if (!stagedContextPattern.test(idea.description)) {
      errors.push(`${idea.code}: controversial description lacks staged or fictional context`);
    }
    if (/(殺す|殺人|自殺)/u.test(idea.title + idea.description)) {
      errors.push(`${idea.code}: killing-related content is not allowed`);
    }
  }

  const idol = allIdeas.filter((idea) => idea.channelTypeCode === "idol");
  for (const idea of idol) {
    if (/(女性向け|男性向け|女子だけ|男子だけ|女の子だけ|男の子だけ)/u.test(idea.title + idea.description)) {
      errors.push(`${idea.code}: overly gender-specific wording detected`);
    }
  }

  const expectedMarkdown = renderSystemIdeasDoc(collections);
  let actualMarkdown = "";
  try {
    actualMarkdown = await readFile(markdownPath, "utf8");
  } catch {
    errors.push("docs/SYSTEM_IDEAS.md is missing");
  }
  if (actualMarkdown && actualMarkdown !== expectedMarkdown) {
    errors.push("docs/SYSTEM_IDEAS.md is out of date; run npm run system-ideas:docs");
  }

  if (errors.length > 0) {
    console.error(`System idea validation failed with ${errors.length} error(s):`);
    errors.forEach((error) => console.error(`- ${error}`));
    process.exitCode = 1;
    return;
  }

  console.log("System idea validation passed.");
  console.log("- mainstream: 50");
  console.log("- controversial: 50");
  console.log("- idol: 50");
  console.log("- specialized: 0");
  console.log("- total: 150");
  console.log("- schema, uniqueness, lengths, staged-context, gender-neutrality, and Markdown sync: OK");
}

await main();
