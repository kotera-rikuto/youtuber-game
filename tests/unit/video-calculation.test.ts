import { describe, expect, it } from "vitest";

import {
  allocateAdjustedViewsToVideos,
  calculateAbilityMultiplier,
  calculateAdRevenue,
  calculateEquipmentMultiplier,
  calculateSubscriberChanges,
  calculateSubscriberMultiplier,
  calculateWeeklyVideoResult,
  resolveIdeaCalculation,
  simulateVideos,
  type IdeaScoreBand,
  type SimulateVideosInput,
} from "@/backend/domain/game/video-calculation";

const IDEA_SCORE_BANDS = [
  {
    minScore: 0,
    maxScore: 39,
    viewMultiplier: 0.5,
    subscriberConversionRate: 0.01,
  },
  {
    minScore: 40,
    maxScore: 59,
    viewMultiplier: 0.8,
    subscriberConversionRate: 0.02,
  },
  {
    minScore: 60,
    maxScore: 79,
    viewMultiplier: 1,
    subscriberConversionRate: 0.03,
  },
  {
    minScore: 80,
    maxScore: 89,
    viewMultiplier: 1.3,
    subscriberConversionRate: 0.04,
  },
  {
    minScore: 90,
    maxScore: 100,
    viewMultiplier: 1.7,
    subscriberConversionRate: 0.05,
  },
] as const satisfies readonly IdeaScoreBand[];

const SYSTEM_IDEA_RULE = {
  viewMultiplier: 0.6,
  subscriberConversionRate: 0.02,
} as const;

describe("calculateSubscriberMultiplier", () => {
  it.each([
    [0, 1],
    [99_999, 1],
    [100_000, 1.5],
    [199_999, 1.5],
    [200_000, 2],
    [500_000, 3.5],
    [1_000_000, 6],
  ])("returns %s subscribers as a %s multiplier", (subscribers, expected) => {
    expect(calculateSubscriberMultiplier(subscribers)).toBe(expected);
  });

  it.each([-1, 1.5, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects invalid subscribers: %s",
    (subscribers) => {
      expect(() => calculateSubscriberMultiplier(subscribers)).toThrow(
        RangeError,
      );
    },
  );
});

describe("calculateAbilityMultiplier", () => {
  it.each([
    [10, 1],
    [50, 1.4],
    [100, 1.9],
  ])("maps an ability average of %s to %s", (abilityValue, expected) => {
    expect(
      calculateAbilityMultiplier(
        [
          { code: "planning", value: abilityValue },
          { code: "talking", value: abilityValue },
        ],
        [
          { abilityCode: "planning", weight: 0.5 },
          { abilityCode: "talking", weight: 0.5 },
        ],
      ),
    ).toBe(expected);
  });

  it("uses the configured ability weights", () => {
    expect(
      calculateAbilityMultiplier(
        [
          { code: "planning", value: 30 },
          { code: "talking", value: 70 },
        ],
        [
          { abilityCode: "planning", weight: 0.25 },
          { abilityCode: "talking", weight: 0.75 },
        ],
      ),
    ).toBe(1.5);
  });

  it("rejects a missing or unknown weighted ability", () => {
    expect(() =>
      calculateAbilityMultiplier(
        [{ code: "planning", value: 50 }],
        [
          { abilityCode: "planning", weight: 0.5 },
          { abilityCode: "unknown", weight: 0.5 },
        ],
      ),
    ).toThrow("Missing ability value: unknown");
  });

  it.each([
    [
      { abilityCode: "planning", weight: 0.4 },
      { abilityCode: "talking", weight: 0.5 },
    ],
    [
      { abilityCode: "planning", weight: 0.5 },
      { abilityCode: "planning", weight: 0.5 },
    ],
  ])("rejects invalid ability weights", (...weights) => {
    expect(() =>
      calculateAbilityMultiplier(
        [
          { code: "planning", value: 50 },
          { code: "talking", value: 50 },
        ],
        weights,
      ),
    ).toThrow(RangeError);
  });

  it("rejects duplicate ability values", () => {
    expect(() =>
      calculateAbilityMultiplier(
        [
          { code: "planning", value: 50 },
          { code: "planning", value: 60 },
        ],
        [
          { abilityCode: "planning", weight: 0.5 },
          { abilityCode: "talking", weight: 0.5 },
        ],
      ),
    ).toThrow("Duplicate ability code");
  });
});

describe("calculateEquipmentMultiplier", () => {
  it.each([
    [[0, 0, 0], 1],
    [[0.05, 0.1, 0.15], 1.3],
    [[0.15, 0.15, 0.15], 1.45],
    [[0.2, 0.2, 0.2], 1.45],
  ])("combines %j as %s", (bonuses, expected) => {
    expect(calculateEquipmentMultiplier(bonuses)).toBe(expected);
  });

  it.each([
    [0, 0],
    [0, 0, -0.1],
    [0, 0, Number.NaN],
  ])("rejects invalid equipment rules", (...bonuses) => {
    expect(() => calculateEquipmentMultiplier(bonuses)).toThrow(RangeError);
  });
});

describe("resolveIdeaCalculation", () => {
  it.each([
    [0, 0.5, 0.01],
    [39, 0.5, 0.01],
    [40, 0.8, 0.02],
    [59, 0.8, 0.02],
    [60, 1, 0.03],
    [79, 1, 0.03],
    [80, 1.3, 0.04],
    [89, 1.3, 0.04],
    [90, 1.7, 0.05],
    [100, 1.7, 0.05],
  ])("resolves player score %s", (score, multiplier, conversionRate) => {
    expect(
      resolveIdeaCalculation(
        { source: "player", score },
        IDEA_SCORE_BANDS,
        SYSTEM_IDEA_RULE,
      ),
    ).toEqual({
      ideaMultiplier: multiplier,
      subscriberConversionRate: conversionRate,
    });
  });

  it("resolves a system idea without an AI score", () => {
    expect(
      resolveIdeaCalculation(
        { source: "system" },
        IDEA_SCORE_BANDS,
        SYSTEM_IDEA_RULE,
      ),
    ).toEqual({
      ideaMultiplier: 0.6,
      subscriberConversionRate: 0.02,
    });
  });

  it.each([-1, 101, 60.5, Number.NaN])("rejects score %s", (score) => {
    expect(() =>
      resolveIdeaCalculation(
        { source: "player", score },
        IDEA_SCORE_BANDS,
        SYSTEM_IDEA_RULE,
      ),
    ).toThrow(RangeError);
  });

  it("rejects rule bands with a gap", () => {
    const incompleteRules: IdeaScoreBand[] = IDEA_SCORE_BANDS.map((band) => ({
      ...band,
    }));
    incompleteRules[1]!.minScore = 41;
    expect(() =>
      resolveIdeaCalculation(
        { source: "player", score: 60 },
        incompleteRules,
        SYSTEM_IDEA_RULE,
      ),
    ).toThrow("without gaps or overlaps");
  });
});

describe("simulateVideos", () => {
  it("applies all seven multipliers and floors once at the end", () => {
    const [video] = simulateVideos(
      simulationInput({
        currentSubscribers: 100_000,
        abilities: [
          { code: "planning", value: 50 },
          { code: "talking", value: 50 },
        ],
        postingFrequencyMultiplier: 1.2,
        channelMultiplier: 1.5,
        equipmentViewBonuses: [0.05, 0.1, 0.15],
        collaborationMultiplier: 1.5,
        videos: [
          {
            videoId: "video-1",
            sequenceNumber: 1,
            baseViews: 101,
            idea: { source: "player", score: 90 },
          },
        ],
      }),
    );

    expect(video).toMatchObject({
      subscriberMultiplier: 1.5,
      abilityMultiplier: 1.4,
      ideaMultiplier: 1.7,
      postingFrequencyMultiplier: 1.2,
      channelMultiplier: 1.5,
      equipmentMultiplier: 1.3,
      collaborationMultiplier: 1.5,
      viewsBeforeEvent: 1265,
    });
  });

  it("does not floor between multipliers", () => {
    const [video] = simulateVideos(
      simulationInput({
        videos: [
          {
            videoId: "video-1",
            sequenceNumber: 1,
            baseViews: 3,
            idea: { source: "player", score: 40 },
          },
        ],
        postingFrequencyMultiplier: 1.2,
      }),
    );
    expect(video?.viewsBeforeEvent).toBe(2);
  });

  it.each([0, 100_000])("accepts base-view boundary %s", (baseViews) => {
    const [video] = simulateVideos(
      simulationInput({
        videos: [
          {
            videoId: "video-1",
            sequenceNumber: 1,
            baseViews,
            idea: { source: "player", score: 60 },
          },
        ],
      }),
    );
    expect(video?.viewsBeforeEvent).toBe(baseViews);
  });

  it("supports multiple videos with mixed idea sources", () => {
    const videos = simulateVideos(
      simulationInput({
        videos: [
          {
            videoId: "player-video",
            sequenceNumber: 1,
            baseViews: 100,
            idea: { source: "player", score: 80 },
          },
          {
            videoId: "system-video",
            sequenceNumber: 2,
            baseViews: 100,
            idea: { source: "system" },
          },
        ],
      }),
    );
    expect(videos.map((video) => video.viewsBeforeEvent)).toEqual([130, 60]);
    expect(videos.map((video) => video.subscriberConversionRate)).toEqual([
      0.04, 0.02,
    ]);
  });

  it.each([-1, 100_001, 1.5, Number.MAX_SAFE_INTEGER + 1])(
    "rejects invalid base views %s",
    (baseViews) => {
      expect(() =>
        simulateVideos(
          simulationInput({
            videos: [
              {
                videoId: "video-1",
                sequenceNumber: 1,
                baseViews,
                idea: { source: "player", score: 60 },
              },
            ],
          }),
        ),
      ).toThrow(RangeError);
    },
  );

  it.each([-0.1, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects invalid multipliers: %s",
    (channelMultiplier) => {
      expect(() =>
        simulateVideos(simulationInput({ channelMultiplier })),
      ).toThrow(RangeError);
    },
  );

  it("rejects a calculation outside the safe integer range", () => {
    expect(() =>
      simulateVideos(
        simulationInput({
          channelMultiplier: Number.MAX_VALUE,
          videos: [
            {
              videoId: "video-1",
              sequenceNumber: 1,
              baseViews: 100_000,
              idea: { source: "player", score: 60 },
            },
          ],
        }),
      ),
    ).toThrow("safe integer range");
  });
});

describe("allocateAdjustedViewsToVideos", () => {
  it.each([
    [2, 12],
    [1, 6],
    [0.5, 3],
  ])("applies event multiplier %s", (eventMultiplier, finalViews) => {
    expect(
      allocateAdjustedViewsToVideos(
        [
          { videoId: "a", sequenceNumber: 1, viewsBeforeEvent: 1 },
          { videoId: "b", sequenceNumber: 2, viewsBeforeEvent: 5 },
        ],
        eventMultiplier,
      ).finalViews,
    ).toBe(finalViews);
  });

  it("floors an odd weekly total after a 0.5 event", () => {
    const result = allocateAdjustedViewsToVideos(
      [
        { videoId: "a", sequenceNumber: 1, viewsBeforeEvent: 2 },
        { videoId: "b", sequenceNumber: 2, viewsBeforeEvent: 3 },
      ],
      0.5,
    );
    expect(result.finalViews).toBe(2);
    expect(result.videos.map((video) => video.finalViews)).toEqual([1, 1]);
  });

  it("gives a remaining view to the larger fractional remainder", () => {
    const result = allocateAdjustedViewsToVideos(
      [
        { videoId: "a", sequenceNumber: 1, viewsBeforeEvent: 1 },
        { videoId: "b", sequenceNumber: 2, viewsBeforeEvent: 2 },
      ],
      0.5,
    );
    expect(result.videos.map((video) => video.finalViews)).toEqual([0, 1]);
  });

  it("uses sequence number for tied remainders without reordering output", () => {
    const result = allocateAdjustedViewsToVideos(
      [
        { videoId: "late", sequenceNumber: 2, viewsBeforeEvent: 1 },
        { videoId: "early", sequenceNumber: 1, viewsBeforeEvent: 1 },
      ],
      0.5,
    );
    expect(result.videos).toEqual([
      {
        videoId: "late",
        sequenceNumber: 2,
        viewsBeforeEvent: 1,
        finalViews: 0,
      },
      {
        videoId: "early",
        sequenceNumber: 1,
        viewsBeforeEvent: 1,
        finalViews: 1,
      },
    ]);
  });

  it("keeps every video at zero when the pre-event total is zero", () => {
    const result = allocateAdjustedViewsToVideos(
      [
        { videoId: "a", sequenceNumber: 1, viewsBeforeEvent: 0 },
        { videoId: "b", sequenceNumber: 2, viewsBeforeEvent: 0 },
      ],
      2,
    );
    expect(result.finalViews).toBe(0);
    expect(result.videos.map((video) => video.finalViews)).toEqual([0, 0]);
  });

  it("always makes allocated views equal the official weekly total", () => {
    const result = allocateAdjustedViewsToVideos(
      [
        { videoId: "a", sequenceNumber: 3, viewsBeforeEvent: 11 },
        { videoId: "b", sequenceNumber: 1, viewsBeforeEvent: 29 },
        { videoId: "c", sequenceNumber: 2, viewsBeforeEvent: 17 },
      ],
      1.37,
    );
    expect(
      result.videos.reduce((total, video) => total + video.finalViews, 0),
    ).toBe(result.finalViews);
  });

  it("rejects duplicate or invalid sequence numbers", () => {
    expect(() =>
      allocateAdjustedViewsToVideos(
        [
          { videoId: "a", sequenceNumber: 1, viewsBeforeEvent: 1 },
          { videoId: "b", sequenceNumber: 1, viewsBeforeEvent: 1 },
        ],
        1,
      ),
    ).toThrow("Duplicate video sequence number");
    expect(() =>
      allocateAdjustedViewsToVideos(
        [{ videoId: "a", sequenceNumber: 0, viewsBeforeEvent: 1 }],
        1,
      ),
    ).toThrow(RangeError);
  });
});

describe("calculateSubscriberChanges", () => {
  it("floors per video before totaling different conversion rates", () => {
    const result = calculateSubscriberChanges([
      { videoId: "a", finalViews: 99, subscriberConversionRate: 0.01 },
      { videoId: "b", finalViews: 49, subscriberConversionRate: 0.02 },
      { videoId: "c", finalViews: 20, subscriberConversionRate: 0.05 },
    ]);
    expect(result.videos.map((video) => video.subscribersGained)).toEqual([
      0, 0, 1,
    ]);
    expect(result.totalSubscribersGained).toBe(1);
  });

  it.each([-0.1, 1.1, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects conversion rate %s",
    (subscriberConversionRate) => {
      expect(() =>
        calculateSubscriberChanges([
          { videoId: "a", finalViews: 100, subscriberConversionRate },
        ]),
      ).toThrow(RangeError);
    },
  );
});

describe("calculateAdRevenue", () => {
  it.each([
    [false, 5, 0],
    [true, 4, 0],
    [true, 5, 1],
    [true, 12_345, 2_469],
  ])(
    "returns %s availability and %s final views as %s yen",
    (isAvailable, views, expected) => {
      expect(calculateAdRevenue(views, 0.2, isAvailable)).toBe(expected);
    },
  );
});

describe("calculateWeeklyVideoResult", () => {
  it("returns a DB-independent, auditable weekly result", () => {
    const result = calculateWeeklyVideoResult({
      ...simulationInput({
        videos: [
          {
            videoId: "player-video",
            sequenceNumber: 2,
            baseViews: 100,
            idea: { source: "player", score: 60 },
          },
          {
            videoId: "system-video",
            sequenceNumber: 1,
            baseViews: 100,
            idea: { source: "system" },
          },
        ],
      }),
      weeklyEventMultiplier: 0.5,
      isAdRevenueAvailable: true,
      adRevenuePerView: 0.2,
    });

    expect(result).toMatchObject({
      viewsBeforeEvent: 160,
      finalViews: 80,
      totalSubscribersGained: 1,
      adRevenue: 16,
    });
    expect(result.videos).toMatchObject([
      {
        videoId: "player-video",
        weeklyEventMultiplier: 0.5,
        finalViews: 50,
        subscribersGained: 1,
      },
      {
        videoId: "system-video",
        weeklyEventMultiplier: 0.5,
        finalViews: 30,
        subscribersGained: 0,
      },
    ]);
  });

  it("is deterministic for the same input", () => {
    const input = {
      ...simulationInput(),
      weeklyEventMultiplier: 1.37,
      isAdRevenueAvailable: true,
      adRevenuePerView: 0.2,
    };
    expect(calculateWeeklyVideoResult(input)).toEqual(
      calculateWeeklyVideoResult(input),
    );
  });
});

function simulationInput(
  overrides: Partial<SimulateVideosInput> = {},
): SimulateVideosInput {
  return {
    videos: [
      {
        videoId: "video-1",
        sequenceNumber: 1,
        baseViews: 100,
        idea: { source: "player", score: 60 },
      },
    ],
    baseViewsRange: { min: 0, max: 100_000 },
    currentSubscribers: 0,
    abilities: [
      { code: "planning", value: 10 },
      { code: "talking", value: 10 },
    ],
    abilityWeights: [
      { abilityCode: "planning", weight: 0.5 },
      { abilityCode: "talking", weight: 0.5 },
    ],
    ideaScoreBands: IDEA_SCORE_BANDS,
    systemIdeaRule: SYSTEM_IDEA_RULE,
    postingFrequencyMultiplier: 1,
    channelMultiplier: 1,
    equipmentViewBonuses: [0, 0, 0],
    collaborationMultiplier: 1,
    ...overrides,
  };
}
