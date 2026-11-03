import { describe, expect, it } from "vitest";

import type { IdeaEvaluator } from "@/backend/application/ports/idea-evaluator";

describe("IdeaEvaluator port", () => {
  it("can be replaced with a fake without importing OpenAI", async () => {
    const fakeEvaluator: IdeaEvaluator = {
      async evaluate() {
        return { score: 73, status: "completed" };
      },
    };

    await expect(
      fakeEvaluator.evaluate({
        title: "テスト企画",
        channelType: "エンタメ系",
        specialty: null,
      }),
    ).resolves.toEqual({ score: 73, status: "completed" });
  });
});
