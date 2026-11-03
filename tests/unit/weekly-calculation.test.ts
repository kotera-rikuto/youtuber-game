import { describe, expect, it } from "vitest";

import {
  applyPostingEnergyCost,
  applyWeeklyMainAction,
  applyWeeklyRandomEventEffect,
  applyWeeklyViewEvent,
  calculateUnavailableWeek,
  PROBABILITY_SCALE,
  rollFlameEvent,
  rollHealthEvent,
  rollWeeklyRandomEvent,
  type HealthRiskRule,
  type IntegerRandomSource,
  type SponsorshipRewardRule,
  type WeeklyEventCategoryRule,
  type WeeklyMainActionRule,
  type WeeklyRandomEvent,
  type WeeklyRandomEventRule,
} from "@/backend/domain/game/weekly-calculation";
import { SequenceRandomSource } from "@/tests/support/sequence-random-source";

const ACTION_RULES = {
  partTimeJob: {
    actionCode: "part_time_job",
    fixedCashDelta: 10_000,
    energyDelta: -10,
    videoViewMultiplier: 1,
  },
  rest: {
    actionCode: "rest",
    fixedCashDelta: 0,
    energyDelta: 50,
    videoViewMultiplier: 1,
  },
  collaboration: {
    actionCode: "collaboration",
    fixedCashDelta: 0,
    energyDelta: -10,
    videoViewMultiplier: 1.5,
  },
  sponsorship: {
    actionCode: "sponsorship",
    fixedCashDelta: 0,
    energyDelta: -5,
    videoViewMultiplier: 1,
  },
} as const satisfies Record<string, WeeklyMainActionRule>;

const SPONSORSHIP_REWARD_RULES = [
  { minSubscribers: 100_000, maxSubscribers: 299_999, rewardAmount: 100_000 },
  { minSubscribers: 300_000, maxSubscribers: 499_999, rewardAmount: 200_000 },
  { minSubscribers: 500_000, maxSubscribers: 999_999, rewardAmount: 400_000 },
  {
    minSubscribers: 1_000_000,
    maxSubscribers: 4_999_999,
    rewardAmount: 800_000,
  },
  {
    minSubscribers: 5_000_000,
    maxSubscribers: 9_999_999,
    rewardAmount: 1_200_000,
  },
  { minSubscribers: 10_000_000, maxSubscribers: null, rewardAmount: 2_000_000 },
] as const satisfies readonly SponsorshipRewardRule[];

const EVENT_CATEGORY_RULES = [
  { categoryCode: "good", weeklyProbability: 0.05 },
  { categoryCode: "bad", weeklyProbability: 0.05 },
] as const satisfies readonly WeeklyEventCategoryRule[];

const EVENT_RULES = [
  {
    code: "featured_in_recommendations",
    categoryCode: "good",
    selectionWeight: 1,
    weeklyViewMultiplier: 2,
    fixedCashDelta: 0,
    fixedSubscriberDelta: 0,
    subscriberMultiplier: 1,
  },
  {
    code: "introduced_by_celebrity",
    categoryCode: "good",
    selectionWeight: 1,
    weeklyViewMultiplier: 1,
    fixedCashDelta: 0,
    fixedSubscriberDelta: 5_000,
    subscriberMultiplier: 1,
  },
  {
    code: "temporary_bonus",
    categoryCode: "good",
    selectionWeight: 1,
    weeklyViewMultiplier: 1,
    fixedCashDelta: 50_000,
    fixedSubscriberDelta: 0,
    subscriberMultiplier: 1,
  },
  {
    code: "poorly_received_video",
    categoryCode: "bad",
    selectionWeight: 1,
    weeklyViewMultiplier: 0.5,
    fixedCashDelta: 0,
    fixedSubscriberDelta: 0,
    subscriberMultiplier: 1,
  },
  {
    code: "equipment_trouble",
    categoryCode: "bad",
    selectionWeight: 1,
    weeklyViewMultiplier: 1,
    fixedCashDelta: -30_000,
    fixedSubscriberDelta: 0,
    subscriberMultiplier: 1,
  },
  {
    code: "criticized_on_social_media",
    categoryCode: "bad",
    selectionWeight: 1,
    weeklyViewMultiplier: 1,
    fixedCashDelta: 0,
    fixedSubscriberDelta: 0,
    subscriberMultiplier: 0.97,
  },
] as const satisfies readonly WeeklyRandomEventRule[];

const HEALTH_RISK_RULES = [
  {
    id: "healthy",
    minEnergy: 50,
    maxEnergy: 100,
    occurrenceProbability: 0,
    minUnavailableWeeks: 0,
    maxUnavailableWeeks: 0,
  },
  {
    id: "low-risk",
    minEnergy: 30,
    maxEnergy: 49,
    occurrenceProbability: 0.05,
    minUnavailableWeeks: 1,
    maxUnavailableWeeks: 2,
  },
  {
    id: "medium-risk",
    minEnergy: 10,
    maxEnergy: 29,
    occurrenceProbability: 0.15,
    minUnavailableWeeks: 3,
    maxUnavailableWeeks: 6,
  },
  {
    id: "high-risk",
    minEnergy: 1,
    maxEnergy: 9,
    occurrenceProbability: 0.3,
    minUnavailableWeeks: 8,
    maxUnavailableWeeks: 12,
  },
] as const satisfies readonly HealthRiskRule[];

const FLAME_GLOBAL_RULE = {
  subscriberLossRate: 0.05,
  energyLoss: 20,
  banFlameCount: 3,
} as const;

describe("applyWeeklyMainAction", () => {
  it.each([
    ["part-time job", ACTION_RULES.partTimeJob, 110_000, 70, 1],
    ["rest", ACTION_RULES.rest, 100_000, 100, 1],
    ["collaboration", ACTION_RULES.collaboration, 100_000, 70, 1.5],
  ])(
    "applies the %s rule",
    (_label, actionRule, expectedCash, expectedEnergy, expectedMultiplier) => {
      expect(
        applyWeeklyMainAction({
          state: { cash: 100_000, energy: 80 },
          actionRule,
          energyMax: 100,
        }),
      ).toEqual({
        cash: expectedCash,
        energy: expectedEnergy,
        videoViewMultiplier: expectedMultiplier,
        sponsorshipReward: 0,
      });
    },
  );

  it("applies a caller-resolved sponsorship reward", () => {
    expect(
      applyWeeklyMainAction({
        state: { cash: 100_000, energy: 80 },
        actionRule: ACTION_RULES.sponsorship,
        energyMax: 100,
        sponsorshipReward: { kind: "resolved-rule", rewardAmount: 400_000 },
      }),
    ).toEqual({
      cash: 500_000,
      energy: 75,
      videoViewMultiplier: 1,
      sponsorshipReward: 400_000,
    });
  });

  it("resolves sponsorship bands only from week-start subscribers", () => {
    expect(
      applyWeeklyMainAction({
        state: { cash: 50_000, energy: 40 },
        actionRule: ACTION_RULES.sponsorship,
        energyMax: 100,
        sponsorshipReward: {
          kind: "reward-bands",
          weekStartSubscribers: 299_999,
          rules: SPONSORSHIP_REWARD_RULES,
        },
      }).sponsorshipReward,
    ).toBe(100_000);
  });

  it("applies rest before posting energy cost", () => {
    const afterRest = applyWeeklyMainAction({
      state: { cash: 0, energy: 75 },
      actionRule: ACTION_RULES.rest,
      energyMax: 100,
    });

    expect(applyPostingEnergyCost(afterRest.energy, { energyCost: 25 })).toBe(
      75,
    );
  });

  it("keeps negative intermediate energy instead of clamping it", () => {
    const afterAction = applyWeeklyMainAction({
      state: { cash: 0, energy: 5 },
      actionRule: ACTION_RULES.partTimeJob,
      energyMax: 100,
    });
    expect(afterAction.energy).toBe(-5);
    expect(applyPostingEnergyCost(afterAction.energy, { energyCost: 25 })).toBe(
      -30,
    );
  });
});

describe("applyPostingEnergyCost", () => {
  it.each([
    [3, 97],
    [8, 92],
    [25, 75],
  ])("uses the fetched energy cost %s", (energyCost, expectedEnergy) => {
    expect(applyPostingEnergyCost(100, { energyCost })).toBe(expectedEnergy);
  });
});

describe("rollWeeklyRandomEvent", () => {
  it.each([
    [1, 1, "good", "featured_in_recommendations"],
    [50_000, 3, "good", "temporary_bonus"],
    [50_001, 1, "bad", "poorly_received_video"],
    [100_000, 3, "bad", "criticized_on_social_media"],
  ])(
    "maps category draw %s to %s",
    (categoryDraw, eventDraw, expectedCategory, expectedCode) => {
      const event = rollWeeklyRandomEvent({
        categoryRules: EVENT_CATEGORY_RULES,
        eventRules: EVENT_RULES,
        randomSource: new SequenceRandomSource([categoryDraw, eventDraw]),
      });
      expect(event?.categoryCode).toBe(expectedCategory);
      expect(event?.rule.code).toBe(expectedCode);
    },
  );

  it.each([100_001, PROBABILITY_SCALE])(
    "returns no event at none-category boundary %s",
    (categoryDraw) => {
      const randomSource = new SequenceRandomSource([categoryDraw]);
      expect(
        rollWeeklyRandomEvent({
          categoryRules: EVENT_CATEGORY_RULES,
          eventRules: EVENT_RULES,
          randomSource,
        }),
      ).toBeNull();
      expect(randomSource.consumedCount).toBe(1);
    },
  );

  it.each([
    [1, 1, "featured_in_recommendations"],
    [1, 2, "introduced_by_celebrity"],
    [1, 3, "temporary_bonus"],
    [50_001, 1, "poorly_received_video"],
    [50_001, 2, "equipment_trouble"],
    [50_001, 3, "criticized_on_social_media"],
  ])(
    "selects category event %s with its independent event draw",
    (categoryDraw, eventDraw, expectedCode) => {
      const event = rollWeeklyRandomEvent({
        categoryRules: EVENT_CATEGORY_RULES,
        eventRules: EVENT_RULES,
        randomSource: new SequenceRandomSource([categoryDraw, eventDraw]),
      });
      expect(event?.rule.code).toBe(expectedCode);
    },
  );

  it("uses configured selection weights", () => {
    const weightedRules = EVENT_RULES.map((rule) => ({
      ...rule,
      selectionWeight:
        rule.code === "introduced_by_celebrity" ? 2 : rule.selectionWeight,
    }));
    const event = rollWeeklyRandomEvent({
      categoryRules: EVENT_CATEGORY_RULES,
      eventRules: weightedRules,
      randomSource: new SequenceRandomSource([1, 3]),
    });
    expect(event?.rule.code).toBe("introduced_by_celebrity");
  });

  it("returns at most one event", () => {
    const event = rollWeeklyRandomEvent({
      categoryRules: EVENT_CATEGORY_RULES,
      eventRules: EVENT_RULES,
      randomSource: new SequenceRandomSource([1, 1]),
    });
    expect(event).toMatchObject({
      categoryCode: "good",
      rule: { code: "featured_in_recommendations" },
    });
    expect(Array.isArray(event)).toBe(false);
  });
});

describe("weekly random event effects", () => {
  it("doubles recommendation views through the BE-025 total calculation", () => {
    expect(
      applyWeeklyViewEvent(
        101,
        eventFor("featured_in_recommendations"),
      ),
    ).toBe(202);
  });

  it("halves poorly received views and floors the result", () => {
    expect(
      applyWeeklyViewEvent(101, eventFor("poorly_received_video")),
    ).toBe(50);
  });

  it("does not allow equipment trouble to create negative cash", () => {
    expect(
      applyWeeklyRandomEventEffect(
        { cash: 10_000, subscribers: 1_000 },
        eventFor("equipment_trouble"),
      ),
    ).toEqual({ cash: 0, subscribers: 1_000 });
  });

  it("floors the three-percent social-media subscriber loss", () => {
    expect(
      applyWeeklyRandomEventEffect(
        { cash: 0, subscribers: 101 },
        eventFor("criticized_on_social_media"),
      ).subscribers,
    ).toBe(97);
  });

  it.each([
    ["introduced_by_celebrity", 10_000, 6_000],
    ["temporary_bonus", 60_000, 1_000],
  ])("applies direct effect for %s", (eventCode, cash, subscribers) => {
    expect(
      applyWeeklyRandomEventEffect(
        { cash: 10_000, subscribers: 1_000 },
        eventFor(eventCode),
      ),
    ).toEqual({ cash, subscribers });
  });
});

describe("rollFlameEvent", () => {
  it.each([
    [0.001, 1_000, true],
    [0.001, 1_001, false],
    [0.05, 50_000, true],
    [0.05, 50_001, false],
  ])(
    "uses the inclusive boundary for probability %s and draw %s",
    (weeklyProbability, draw, occurred) => {
      expect(
        rollFlameEvent({
          state: flameState(),
          weeklyProbability,
          globalRule: FLAME_GLOBAL_RULE,
          randomSource: new SequenceRandomSource([draw]),
        }).occurred,
      ).toBe(occurred);
    },
  );

  it("reduces subscribers and energy, increments count, and preserves views", () => {
    expect(
      rollFlameEvent({
        state: flameState({
          subscribers: 101,
          energy: 45,
          flameCount: 1,
          weeklyViews: 12_345,
        }),
        weeklyProbability: 0.05,
        globalRule: FLAME_GLOBAL_RULE,
        randomSource: new SequenceRandomSource([1]),
      }),
    ).toEqual({
      occurred: true,
      state: {
        subscribers: 95,
        energy: 25,
        flameCount: 2,
        weeklyViews: 12_345,
      },
    });
  });

  it("is independent from the weekly random-event draw", () => {
    const randomSource = new SequenceRandomSource([1, 2, 1]);
    const weeklyEvent = rollWeeklyRandomEvent({
      categoryRules: EVENT_CATEGORY_RULES,
      eventRules: EVENT_RULES,
      randomSource,
    });
    const flame = rollFlameEvent({
      state: flameState(),
      weeklyProbability: 0.05,
      globalRule: FLAME_GLOBAL_RULE,
      randomSource,
    });

    expect(weeklyEvent?.rule.code).toBe("introduced_by_celebrity");
    expect(flame.occurred).toBe(true);
    expect(randomSource.consumedCount).toBe(3);
  });

  it("still rolls flame when the weekly event is none", () => {
    const randomSource = new SequenceRandomSource([100_001, 1]);
    expect(
      rollWeeklyRandomEvent({
        categoryRules: EVENT_CATEGORY_RULES,
        eventRules: EVENT_RULES,
        randomSource,
      }),
    ).toBeNull();
    expect(
      rollFlameEvent({
        state: flameState(),
        weeklyProbability: 0.05,
        globalRule: FLAME_GLOBAL_RULE,
        randomSource,
      }).occurred,
    ).toBe(true);
    expect(randomSource.consumedCount).toBe(2);
  });
});

describe("rollHealthEvent", () => {
  it("does not consume randomness for the zero-percent healthy band", () => {
    const randomSource = new SequenceRandomSource([]);
    expect(
      rollHealthEvent({
        currentWeek: 10,
        energy: 50,
        healthRiskRules: HEALTH_RISK_RULES,
        randomSource,
      }),
    ).toBeNull();
    expect(randomSource.consumedCount).toBe(0);
  });

  it.each([
    [30, 50_000, 1, "low-risk", 1],
    [10, 150_000, 3, "medium-risk", 3],
    [1, 300_000, 8, "high-risk", 8],
  ])(
    "resolves energy %s to its risk band",
    (energy, probabilityDraw, durationDraw, ruleId, durationWeeks) => {
      expect(
        rollHealthEvent({
          currentWeek: 10,
          energy,
          healthRiskRules: HEALTH_RISK_RULES,
          randomSource: new SequenceRandomSource([
            probabilityDraw,
            durationDraw,
          ]),
        }),
      ).toEqual({
        healthRiskRuleId: ruleId,
        durationWeeks,
        unavailableFromWeek: 11,
        unavailableThroughWeek: 10 + durationWeeks,
      });
    },
  );

  it("does not occur just above a health probability boundary", () => {
    const randomSource = new SequenceRandomSource([50_001]);
    expect(
      rollHealthEvent({
        currentWeek: 10,
        energy: 49,
        healthRiskRules: HEALTH_RISK_RULES,
        randomSource,
      }),
    ).toBeNull();
    expect(randomSource.consumedCount).toBe(1);
  });

  it.each([3, 6])(
    "can select duration boundary %s inclusively",
    (durationWeeks) => {
      expect(
        rollHealthEvent({
          currentWeek: 20,
          energy: 20,
          healthRiskRules: HEALTH_RISK_RULES,
          randomSource: new SequenceRandomSource([1, durationWeeks]),
        })?.durationWeeks,
      ).toBe(durationWeeks);
    },
  );

  it("requests the configured inclusive integer duration range", () => {
    const randomSource = new RecordingRandomSource([1, 6]);
    rollHealthEvent({
      currentWeek: 20,
      energy: 20,
      healthRiskRules: HEALTH_RISK_RULES,
      randomSource,
    });
    expect(randomSource.requests).toEqual([
      [1, PROBABILITY_SCALE],
      [3, 6],
    ]);
  });

  it.each([0, -1])(
    "skips health resolution and randomness at energy %s",
    (energy) => {
      const randomSource = new SequenceRandomSource([]);
      expect(
        rollHealthEvent({
          currentWeek: 10,
          energy,
          healthRiskRules: [],
          randomSource,
        }),
      ).toBeNull();
      expect(randomSource.consumedCount).toBe(0);
    },
  );

  it("does not roll health when flame leaves energy at zero", () => {
    const randomSource = new SequenceRandomSource([1]);
    const flame = rollFlameEvent({
      state: flameState({ energy: 20 }),
      weeklyProbability: 0.05,
      globalRule: FLAME_GLOBAL_RULE,
      randomSource,
    });
    expect(flame.state.energy).toBe(0);
    expect(
      rollHealthEvent({
        currentWeek: 10,
        energy: flame.state.energy,
        healthRiskRules: HEALTH_RISK_RULES,
        randomSource,
      }),
    ).toBeNull();
    expect(randomSource.consumedCount).toBe(1);
  });
});

describe("calculateUnavailableWeek", () => {
  it.each([
    [40, 50],
    [95, 100],
    [100, 100],
  ])("recovers energy %s to %s and skips weekly systems", (energy, expected) => {
    expect(
      calculateUnavailableWeek({
        energy,
        energyRecovery: 10,
        energyMax: 100,
      }),
    ).toEqual({
      energyAfter: expected,
      postedVideoCount: 0,
      mainActionApplied: false,
      randomEvent: null,
      flameOccurred: false,
      healthEvent: null,
      abilityPointsAwarded: 0,
    });
  });
});

describe("weekly calculation determinism", () => {
  it("returns identical results for the same inputs and integer sequence", () => {
    expect(runDeterministicScenario()).toEqual(runDeterministicScenario());
  });
});

function eventFor(code: string): WeeklyRandomEvent {
  const rule = EVENT_RULES.find((candidate) => candidate.code === code);
  if (rule === undefined) {
    throw new Error(`Missing test event rule: ${code}`);
  }
  return { categoryCode: rule.categoryCode, rule };
}

function flameState(overrides: Partial<ReturnType<typeof flameStateBase>> = {}) {
  return { ...flameStateBase(), ...overrides };
}

function flameStateBase() {
  return {
    subscribers: 10_000,
    energy: 60,
    flameCount: 0,
    weeklyViews: 20_000,
  };
}

function runDeterministicScenario() {
  const randomSource = new SequenceRandomSource([
    50_001,
    3,
    50_000,
    150_000,
    6,
  ]);
  const weeklyEvent = rollWeeklyRandomEvent({
    categoryRules: EVENT_CATEGORY_RULES,
    eventRules: EVENT_RULES,
    randomSource,
  });
  const eventState = applyWeeklyRandomEventEffect(
    { cash: 50_000, subscribers: 10_000 },
    weeklyEvent,
  );
  const flame = rollFlameEvent({
    state: {
      subscribers: eventState.subscribers,
      energy: 40,
      flameCount: 0,
      weeklyViews: applyWeeklyViewEvent(20_001, weeklyEvent),
    },
    weeklyProbability: 0.05,
    globalRule: FLAME_GLOBAL_RULE,
    randomSource,
  });
  const health = rollHealthEvent({
    currentWeek: 12,
    energy: flame.state.energy,
    healthRiskRules: HEALTH_RISK_RULES,
    randomSource,
  });
  return { weeklyEvent, eventState, flame, health };
}

class RecordingRandomSource implements IntegerRandomSource {
  readonly requests: [number, number][] = [];
  private nextIndex = 0;

  constructor(private readonly values: readonly number[]) {}

  nextInt(minInclusive: number, maxInclusive: number): number {
    this.requests.push([minInclusive, maxInclusive]);
    const value = this.values[this.nextIndex];
    if (value === undefined) {
      throw new Error("No recorded random value remains.");
    }
    this.nextIndex += 1;
    return value;
  }
}
