import { requireUseCaseContext } from "@/backend/application/auth/authentication";
import {
  startGame,
  type StartGameInput,
} from "@/backend/application/use-cases/start-game";
import type { GameRun } from "@/backend/domain/game/game-run";
import {
  InMemoryGameRunRepository,
  InMemoryRuleRepository,
} from "@/tests/support/in-memory-repositories";
import { describe, expect, it } from "vitest";

const activeRuleSet = {
  id: "active-rules",
  version: "1.0.0",
  status: "active" as const,
  publishedAt: new Date("2026-11-01T00:00:00.000Z"),
};
const postingStyles = [
  "mainstream",
  "specialized",
  "controversial",
  "idol",
] as const;
const specialties = [
  "baseball",
  "soccer",
  "gaming",
  "pc_gadgets",
  "science",
  "history_culture",
  "occult",
  "nature",
  "food_culture",
  "outdoor_survival",
] as const;

describe("startGame", () => {
  it.each(["mainstream", "controversial", "idol"] as const)(
    "starts a %s channel with one atomic command",
    async (postingStyle) => {
      const dependencies = createDependencies();
      const context = await contextFor("actor-user");

      await expect(
        startGame(
          context,
          { channelName: "  テストチャンネル  ", postingStyle },
          dependencies,
        ),
      ).resolves.toEqual({ runId: "created-run-id" });

      expect(dependencies.gameRuns.commitStartGameCalls).toEqual([
        {
          actorUserId: context.actorUserId,
          channelName: "テストチャンネル",
          postingStyle,
          specialtyCode: null,
        },
      ]);
    },
  );

  it("starts a specialized channel with an enabled specialty", async () => {
    const dependencies = createDependencies();
    const context = await contextFor("actor-user");

    await expect(
      startGame(
        context,
        {
          channelName: "ゲーム研究所",
          postingStyle: "specialized",
          specialtyCode: "gaming",
        },
        dependencies,
      ),
    ).resolves.toEqual({ runId: "created-run-id" });
    expect(dependencies.gameRuns.commitStartGameCalls).toHaveLength(1);
  });

  it("rejects a specialized channel without a specialty", async () => {
    await expectInvalidInput(
      {
        channelName: "専門チャンネル",
        postingStyle: "specialized",
      } as StartGameInput,
      "SPECIALTY_REQUIRED",
    );
  });

  it("rejects a specialty for a non-specialized channel", async () => {
    await expectInvalidInput(
      {
        channelName: "王道チャンネル",
        postingStyle: "mainstream",
        specialtyCode: "gaming",
      } as unknown as StartGameInput,
      "SPECIALTY_NOT_ALLOWED",
    );
  });

  it("rejects a specialty outside the public input catalog", async () => {
    await expectInvalidInput(
      {
        channelName: "専門チャンネル",
        postingStyle: "specialized",
        specialtyCode: "invalid",
      } as unknown as StartGameInput,
      "SPECIALTY_NOT_ALLOWED",
    );
  });

  it("rejects a specialty disabled in the active rule set", async () => {
    const dependencies = createDependencies({ enabledSpecialties: [] });
    const context = await contextFor("actor-user");

    await expect(
      startGame(
        context,
        {
          channelName: "専門チャンネル",
          postingStyle: "specialized",
          specialtyCode: "gaming",
        },
        dependencies,
      ),
    ).rejects.toMatchObject({ code: "SPECIALTY_NOT_ALLOWED" });
    expect(dependencies.gameRuns.commitStartGameCalls).toHaveLength(0);
  });

  it("rejects an empty channel name", async () => {
    await expectInvalidInput(
      { channelName: " \n\t ", postingStyle: "mainstream" },
      "VALIDATION_ERROR",
    );
  });

  it("rejects an unknown posting style", async () => {
    await expectInvalidInput(
      {
        channelName: "不正スタイル",
        postingStyle: "invalid",
      } as unknown as StartGameInput,
      "VALIDATION_ERROR",
    );
  });

  it("uses only the verified context as owner", async () => {
    const dependencies = createDependencies();
    const context = await contextFor("verified-actor");
    const untrustedInput = {
      channelName: "安全なチャンネル",
      postingStyle: "mainstream",
      userId: "forged-user",
    } as unknown as StartGameInput;

    await startGame(context, untrustedInput, dependencies);

    expect(dependencies.gameRuns.commitStartGameCalls[0]?.actorUserId).toBe(
      context.actorUserId,
    );
    expect(dependencies.gameRuns.commitStartGameCalls[0]).not.toHaveProperty(
      "userId",
    );
  });

  it("rejects a second active game before committing", async () => {
    const context = await contextFor("actor-user");
    const dependencies = createDependencies({ runs: [activeRun("actor-user")] });

    await expect(
      startGame(
        context,
        { channelName: "二つ目", postingStyle: "mainstream" },
        dependencies,
      ),
    ).rejects.toMatchObject({ code: "ACTIVE_GAME_EXISTS" });
    expect(dependencies.gameRuns.commitStartGameCalls).toHaveLength(0);
  });
});

async function expectInvalidInput(
  input: StartGameInput,
  code: string,
) {
  const dependencies = createDependencies();
  const context = await contextFor("actor-user");

  await expect(startGame(context, input, dependencies)).rejects.toMatchObject({
    code,
  });
  expect(dependencies.gameRuns.commitStartGameCalls).toHaveLength(0);
}

function createDependencies(options: {
  runs?: readonly GameRun[];
  enabledSpecialties?: readonly (typeof specialties)[number][];
} = {}) {
  const gameRuns = new InMemoryGameRunRepository(options.runs);
  const rules = new InMemoryRuleRepository({
    ruleSets: [activeRuleSet],
    channelRules: postingStyles.map((postingStyle) => ({
      id: `${postingStyle}-rule`,
      ruleSetId: activeRuleSet.id,
      channelTypeCode: postingStyle,
      viewMultiplier: 1,
      weeklyFlameProbability: 0,
    })),
    specialties: (options.enabledSpecialties ?? specialties).map(
      (specialtyCode) => ({
        ruleSetId: activeRuleSet.id,
        specialtyCode,
      }),
    ),
  });

  return { gameRuns, rules };
}

function activeRun(ownerUserId: string): GameRun {
  return {
    id: "active-run",
    ownerUserId,
    ruleSetId: activeRuleSet.id,
    channelName: "進行中",
    channelType: { code: "mainstream", name: "王道系" },
    specialty: null,
    status: "playing",
    createdAt: new Date("2026-11-01T00:00:00.000Z"),
    completedAt: null,
    currentState: {
      currentWeek: 1,
      stateVersion: 0,
      postingFrequency: 1,
      cash: 100_000,
      energy: 100,
      subscribers: 0,
      cumulativeViews: 0,
      flameCount: 0,
      updatedAt: new Date("2026-11-01T00:00:00.000Z"),
    },
    abilities: [],
    equipment: [],
    currentGoal: null,
    unlockedFeatures: [],
  };
}

function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
