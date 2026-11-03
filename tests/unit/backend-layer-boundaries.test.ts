import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const projectRoot = fileURLToPath(new URL("../..", import.meta.url));

describe("backend layer boundaries", () => {
  it.each([
    "backend/application/ports/create-idea-repository.ts",
    "backend/application/ports/game-run-repository.ts",
    "backend/application/ports/idea-stock-repository.ts",
    "backend/application/ports/rule-repository.ts",
    "backend/application/ports/week-result-repository.ts",
    "backend/domain/game/game-run.ts",
    "backend/domain/game/idea-creation.ts",
    "backend/domain/game/idea-stock.ts",
    "backend/domain/game/rules.ts",
    "backend/domain/game/video-calculation.ts",
    "backend/domain/game/week-result.ts",
  ])("does not require Supabase from %s", (relativePath) => {
    const source = readFileSync(join(projectRoot, relativePath), "utf8");
    expect(source).not.toMatch(/@supabase|database\.types|PostgrestError/);
  });
});
