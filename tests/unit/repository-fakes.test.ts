import { describe, expect, it } from "vitest";

import { requireUseCaseContext } from "@/backend/application/auth/authentication";
import type { GameRunRepository } from "@/backend/application/ports/game-run-repository";
import type { IdeaStockRepository } from "@/backend/application/ports/idea-stock-repository";
import type { RuleRepository } from "@/backend/application/ports/rule-repository";
import type { WeekResultRepository } from "@/backend/application/ports/week-result-repository";
import {
  InMemoryGameRunRepository,
  InMemoryIdeaStockRepository,
  InMemoryRuleRepository,
  InMemoryWeekResultRepository,
} from "@/tests/support/in-memory-repositories";

describe("repository fakes", () => {
  it("implement the production ports and keep instances independent", async () => {
    const first = new InMemoryIdeaStockRepository([
      {
        ownerUserId: "user-1",
        queue: {
          runId: "run-1",
          items: [
            {
              id: "idea-1",
              position: 1,
              title: "テスト企画",
              description: null,
              createdWeek: 1,
              createdAt: new Date("2026-11-01T00:00:00.000Z"),
              queuedAt: new Date("2026-11-01T00:01:00.000Z"),
            },
          ],
        },
        createdCountByWeek: { 1: 2 },
      },
    ]);
    const second = new InMemoryIdeaStockRepository();
    const context = await contextFor("user-1");

    await expect(
      first.countPending({ actorUserId: context.actorUserId, runId: "run-1" }),
    ).resolves.toBe(1);
    await expect(
      second.countPending({ actorUserId: context.actorUserId, runId: "run-1" }),
    ).resolves.toBeNull();
    expect(first.countPendingCalls).toHaveLength(1);
    expect(second.countPendingCalls).toHaveLength(1);
  });

  it("does not return a fixture to a different actor", async () => {
    const repository = new InMemoryIdeaStockRepository([
      {
        ownerUserId: "owner-user",
        queue: { runId: "run-1", items: [] },
      },
    ]);
    const otherUser = await contextFor("other-user");

    await expect(
      repository.getPendingQueue({
        actorUserId: otherUser.actorUserId,
        runId: "run-1",
      }),
    ).resolves.toBeNull();
  });

  it("can inject every fake through its application port", () => {
    const gameRuns: GameRunRepository = new InMemoryGameRunRepository();
    const ideaStock: IdeaStockRepository = new InMemoryIdeaStockRepository();
    const rules: RuleRepository = new InMemoryRuleRepository();
    const weekResults: WeekResultRepository =
      new InMemoryWeekResultRepository();

    expect({ gameRuns, ideaStock, rules, weekResults }).toBeDefined();
  });
});

async function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
