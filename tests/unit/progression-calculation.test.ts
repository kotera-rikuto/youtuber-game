import { describe, expect, it } from "vitest";

import {
  checkFeatureUnlocks,
  checkGameOver,
  checkStageGoal,
  replaceAbilityPointsForNextWeek,
  type GameOverCheckInput,
  type GameOverCheckResult,
  type FeatureUnlockRule,
} from "@/backend/domain/game/progression-calculation";

const FEATURE_RULES: readonly FeatureUnlockRule[] = [
  {
    id: "ads",
    featureCode: "advertising",
    unlockSubscribers: 3_000,
    activationDelayWeeks: 1,
  },
  {
    id: "collaboration",
    featureCode: "collaboration",
    unlockSubscribers: 50_000,
    activationDelayWeeks: 1,
  },
  {
    id: "sponsorship",
    featureCode: "sponsorship",
    unlockSubscribers: 100_000,
    activationDelayWeeks: 1,
  },
];

describe("replaceAbilityPointsForNextWeek", () => {
  it.each([
    [1, 3],
    [3, 7],
    [7, 15],
  ])("uses the fetched award for %s videos", (videosPerWeek, award) => {
    const result = replaceAbilityPointsForNextWeek({
      weekKind: "normal",
      healthConditionStarted: false,
      currentWeek: 10,
      abilityPointsAwarded: award,
      newPointsAvailableFromWeek: 11,
      existingGrants: [],
    });
    expect(result).toMatchObject({
      newGrant: { amount: award, status: "available" },
    });
    expect(videosPerWeek).toBeGreaterThan(0);
  });

  it("replaces unused grants and preserves the input", () => {
    const existingGrants = [
      { grantId: "available", status: "available" as const, remainingPoints: 2 },
      { grantId: "held", status: "held" as const, remainingPoints: 4 },
      { grantId: "consumed", status: "consumed" as const, remainingPoints: 0 },
    ];
    const before = structuredClone(existingGrants);

    expect(
      replaceAbilityPointsForNextWeek({
        weekKind: "normal",
        healthConditionStarted: false,
        currentWeek: 10,
        abilityPointsAwarded: 7,
        newPointsAvailableFromWeek: 11,
        existingGrants,
      }),
    ).toEqual({
      outcome: "replaced",
      expiredGrantIds: ["available", "held"],
      newGrant: {
        earnedWeek: 10,
        availableFromWeek: 11,
        amount: 7,
        status: "available",
      },
    });
    expect(existingGrants).toEqual(before);
  });

  it("holds all existing points during an unavailable week", () => {
    expect(
      replaceAbilityPointsForNextWeek({
        weekKind: "activity_unavailable",
        healthConditionStarted: false,
        currentWeek: 10,
        abilityPointsAwarded: 0,
        newPointsAvailableFromWeek: 11,
        existingGrants: [
          { grantId: "held", status: "held", remainingPoints: 4 },
        ],
      }),
    ).toEqual({
      outcome: "held",
      expiredGrantIds: [],
      newGrant: null,
      retainedGrantIds: ["held"],
    });
  });

  it("holds a new grant when a health condition starts", () => {
    expect(
      replaceAbilityPointsForNextWeek({
        weekKind: "normal",
        healthConditionStarted: true,
        currentWeek: 10,
        abilityPointsAwarded: 7,
        newPointsAvailableFromWeek: 11,
        existingGrants: [],
      }),
    ).toMatchObject({
      outcome: "replaced",
      newGrant: { status: "held" },
    });
  });

  it("accepts zero as the minimum award without creating an unavailable-week grant", () => {
    expect(
      replaceAbilityPointsForNextWeek({
        weekKind: "activity_unavailable",
        healthConditionStarted: false,
        currentWeek: 1,
        abilityPointsAwarded: 0,
        newPointsAvailableFromWeek: 2,
        existingGrants: [],
      }),
    ).toEqual({
      outcome: "held",
      expiredGrantIds: [],
      newGrant: null,
      retainedGrantIds: [],
    });
  });

  it("rejects invalid award and week values", () => {
    expect(() =>
      replaceAbilityPointsForNextWeek({
        weekKind: "normal",
        healthConditionStarted: false,
        currentWeek: 0,
        abilityPointsAwarded: -1,
        newPointsAvailableFromWeek: 1,
        existingGrants: [],
      }),
    ).toThrow(RangeError);
  });
});

describe("checkFeatureUnlocks", () => {
  it.each([
    [2_999, []],
    [3_000, ["ads"]],
    [50_000, ["ads", "collaboration"]],
    [100_000, ["ads", "collaboration", "sponsorship"]],
  ])("uses the weekly maximum at %s subscribers", (maximum, expectedIds) => {
    const result = checkFeatureUnlocks({
      currentWeek: 20,
      maxSubscribersDuringWeek: maximum,
      featureRules: FEATURE_RULES,
      unlockedFeatureRuleIds: [],
    });
    expect(result.unlocks.map((unlock) => unlock.featureRuleId)).toEqual(
      expectedIds,
    );
  });

  it("does not relock or duplicate an unlocked feature", () => {
    const result = checkFeatureUnlocks({
      currentWeek: 20,
      maxSubscribersDuringWeek: 2_000,
      featureRules: FEATURE_RULES,
      unlockedFeatureRuleIds: ["ads"],
    });
    expect(result.unlocks).toEqual([]);
  });

  it("uses each rule delay for activation", () => {
    const result = checkFeatureUnlocks({
      currentWeek: 20,
      maxSubscribersDuringWeek: 3_000,
      featureRules: [
        { ...FEATURE_RULES[0]!, activationDelayWeeks: 2 },
      ],
      unlockedFeatureRuleIds: [],
    });
    expect(result.unlocks[0]).toMatchObject({
      unlockedWeek: 20,
      activeFromWeek: 22,
    });
  });

  it("rejects duplicate and negative rules", () => {
    expect(() =>
      checkFeatureUnlocks({
        currentWeek: 1,
        maxSubscribersDuringWeek: 0,
        featureRules: [
          { ...FEATURE_RULES[0]!, unlockSubscribers: -1 },
          FEATURE_RULES[0]!,
        ],
        unlockedFeatureRuleIds: [],
      }),
    ).toThrow(RangeError);
  });
});

describe("checkStageGoal", () => {
  const goalRule = {
    targetSubscribers: 100_000,
    startedWeek: 1,
    deadlineWeek: 156,
    isFinal: false,
  } as const;

  it.each([
    [10, 99_999, "active"],
    [10, 100_000, "stage_cleared"],
    [156, 100_000, "stage_cleared"],
    [156, 99_999, "deadline"],
  ])("returns %s for week %s and %s subscribers", (week, subscribers, outcome) => {
    expect(
      checkStageGoal({ currentWeek: week, subscribers, goalRule }),
    ).toEqual({ outcome });
  });

  it("returns cleared for the final stage", () => {
    expect(
      checkStageGoal({
        currentWeek: 156,
        subscribers: 100_000,
        goalRule: { ...goalRule, isFinal: true },
      }),
    ).toEqual({ outcome: "cleared" });
  });

  it("rejects an invalid week range", () => {
    expect(() =>
      checkStageGoal({
        currentWeek: 1,
        subscribers: 0,
        goalRule: { ...goalRule, startedWeek: 2 },
      }),
    ).toThrow(RangeError);
  });
});

describe("checkGameOver", () => {
  const baseInput: GameOverCheckInput = {
    energy: 10,
    flameCount: 0,
    banFlameCount: 3,
    stageGoalOutcome: "active" as const,
  };

  const cases = [
    [baseInput, "continue"],
    [{ ...baseInput, flameCount: 3 }, "flame_ban"],
    [{ ...baseInput, energy: 0 }, "death"],
    [{ ...baseInput, energy: -1 }, "death"],
    [{ ...baseInput, stageGoalOutcome: "deadline" }, "deadline"],
    [
      { ...baseInput, flameCount: 3, energy: 0, stageGoalOutcome: "cleared" },
      "flame_ban",
    ],
  ] satisfies readonly [GameOverCheckInput, GameOverCheckResult["outcome"]][];

  it.each(cases)("returns %s", (input, outcome) => {
    expect(checkGameOver(input)).toMatchObject({ outcome });
  });

  it("returns calculated values for a fatal command", () => {
    expect(
      checkGameOver({
        ...baseInput,
        energy: -5,
        flameCount: 2,
      }),
    ).toEqual({
      outcome: "death",
      calculatedEnergy: -5,
      calculatedFlameCount: 2,
    });
  });

  it("uses the supplied ban threshold", () => {
    expect(
      checkGameOver({ ...baseInput, flameCount: 2, banFlameCount: 2 }),
    ).toMatchObject({ outcome: "flame_ban" });
  });
});
