import { execFileSync } from "node:child_process";
import { mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const outputPath = resolve(
  "backend/infrastructure/supabase/database.types.ts",
);
const temporaryOutputPath = `${outputPath}.tmp`;
const supabaseCommand = process.platform === "win32" ? "supabase.cmd" : "supabase";

function generateDatabaseTypes() {
  return execFileSync(
    supabaseCommand,
    ["gen", "types", "typescript", "--local", "--schema", "public"],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "inherit"],
    },
  );
}

function normalizeGeneratedTypes(generatedTypes) {
  return `${generatedTypes.replace(/[\t ]+$/gm, "").trimEnd()}\n`;
}

try {
  const generatedTypes = normalizeGeneratedTypes(generateDatabaseTypes());

  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(temporaryOutputPath, generatedTypes);
  renameSync(temporaryOutputPath, outputPath);
} finally {
  rmSync(temporaryOutputPath, { force: true });
}
