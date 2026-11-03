import { describe, expect, it } from "vitest";

import { requireUseCaseContext } from "@/backend/application/auth/authentication";
import type { GameRunRepository } from "@/backend/application/ports/game-run-repository";
import type { IdeaStockRepository } from "@/backend/application/ports/idea-stock-repository";
import type { RuleRepository } from "@/backend/application/ports/rule-repository";
import type { WeekResultRepository } from "@/backend/application/ports/week-result-repository";
import type { WeekEvent, WeekResult } from "@/backend/domain/game/week-result";
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

  describe("InMemoryWeekResultRepository", () => {
    it("returns an empty history for an owned run with no results", async () => {
      const owner = await contextFor("owner-user");
      const repository = new InMemoryWeekResultRepository({
        ownedRuns: [{ ownerUserId: "owner-user", runId: "empty-run" }],
      });

      await expect(
        repository.listHistory({
          actorUserId: owner.actorUserId,
          runId: "empty-run",
        }),
      ).resolves.toEqual([]);
    });

    it("returns null for a run the actor does not own", async () => {
      const other = await contextFor("other-user");
      const repository = createWeekResultRepository();

      await expect(
        repository.listHistory({
          actorUserId: other.actorUserId,
          runId: "owned-run",
        }),
      ).resolves.toBeNull();
    });

    it("returns an owned history in week-number order", async () => {
      const owner = await contextFor("owner-user");
      const repository = createWeekResultRepository();

      const history = await repository.listHistory({
        actorUserId: owner.actorUserId,
        runId: "owned-run",
      });

      expect(history?.map((result) => result.weekNumber)).toEqual([1, 3]);
    });

    it("finds owned results by week and idempotency key", async () => {
      const owner = await contextFor("owner-user");
      const repository = createWeekResultRepository();
      const query = {
        actorUserId: owner.actorUserId,
        runId: "owned-run",
      };

      await expect(
        repository.findCommittedWeek({ ...query, weekNumber: 3 }),
      ).resolves.toMatchObject({ weekNumber: 3 });
      await expect(
        repository.findByIdempotencyKey({
          ...query,
          idempotencyKey: "week-1-key",
        }),
      ).resolves.toMatchObject({ weekNumber: 1 });
    });

    it("does not return results to a different actor", async () => {
      const other = await contextFor("other-user");
      const repository = createWeekResultRepository();

      await expect(
        repository.findCommittedWeek({
          actorUserId: other.actorUserId,
          runId: "owned-run",
          weekNumber: 1,
        }),
      ).resolves.toBeNull();
    });

    it("returns null when an owned run has no result for the requested week", async () => {
      const owner = await contextFor("owner-user");
      const repository = createWeekResultRepository();

      await expect(
        repository.findCommittedWeek({
          actorUserId: owner.actorUserId,
          runId: "owned-run",
          weekNumber: 2,
        }),
      ).resolves.toBeNull();
    });

    it("returns null when an owned run has no result for the idempotency key", async () => {
      const owner = await contextFor("owner-user");
      const repository = createWeekResultRepository();

      await expect(
        repository.findByIdempotencyKey({
          actorUserId: owner.actorUserId,
          runId: "owned-run",
          idempotencyKey: "missing-key",
        }),
      ).resolves.toBeNull();
    });

    it("protects its internal dates and arrays from returned-value mutation", async () => {
      const owner = await contextFor("owner-user");
      const repository = createWeekResultRepository();
      const query = {
        actorUserId: owner.actorUserId,
        runId: "owned-run",
      };
      const firstHistory = await repository.listHistory(query);
      if (!firstHistory?.[0]) {
        throw new Error("Expected the fake history fixture.");
      }
      firstHistory[0].createdAt.setUTCFullYear(2000);
      (firstHistory[0].events as WeekEvent[]).push({
        code: "mutated",
        name: "mutated",
        sequenceNumber: 2,
        displayMetadata: null,
      });

      const secondHistory = await repository.listHistory(query);

      expect(secondHistory?.[0]?.createdAt).toEqual(
        new Date("2026-11-01T00:00:00.000Z"),
      );
      expect(secondHistory?.[0]?.events).toHaveLength(1);
    });
  });
});

async function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}

function createWeekResultRepository() {
  return new InMemoryWeekResultRepository({
    ownedRuns: [{ ownerUserId: "owner-user", runId: "owned-run" }],
    results: [
      { result: weekResult(3), idempotencyKey: "week-3-key" },
      { result: weekResult(1), idempotencyKey: "week-1-key" },
    ],
  });
}

function weekResult(weekNumber: number): WeekResult {
  return {
    id: `result-${weekNumber}`,
    runId: "owned-run",
    weekNumber,
    stageNumber: 1,
    action: { code: "rest", name: "休む" },
    plannedVideoCount: 1,
    postedVideoCount: 1,
    viewsBeforeEvent: 100,
    finalViews: 100,
    eventViewChange: 0,
    subscribersBefore: 10,
    maxSubscribersDuringWeek: 11,
    subscribersAfter: 11,
    subscriberChange: 1,
    energyBefore: 100,
    energyAfter: 90,
    energyChange: -10,
    cashBefore: 1000,
    cashAfter: 1000,
    cashChange: 0,
    adRevenue: 0,
    flameCountBefore: 0,
    flameCountAfter: 0,
    flameCountChange: 0,
    hadFlame: false,
    healthCondition: null,
    wasActivityUnavailable: false,
    runStatusAfter: "playing",
    stateVersionAfter: weekNumber,
    createdAt: new Date("2026-11-01T00:00:00.000Z"),
    events: [
      {
        code: "none",
        name: "イベントなし",
        sequenceNumber: 1,
        displayMetadata: null,
      },
    ],
  };
}
