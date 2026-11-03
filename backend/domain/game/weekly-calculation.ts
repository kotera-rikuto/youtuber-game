import {
  calculateAdjustedWeeklyViews,
  multiplyNonnegativeIntegerAndFloor,
} from "./video-calculation";

export const PROBABILITY_SCALE = 1_000_000;

export const WEEKLY_MAIN_ACTION_CODES = [
  "part_time_job",
  "rest",
  "collaboration",
  "sponsorship",
] as const;

export type WeeklyMainActionCode =
  (typeof WEEKLY_MAIN_ACTION_CODES)[number];

export interface IntegerRandomSource {
  nextInt(minInclusive: number, maxInclusive: number): number;
}

export type WeeklyMainActionRule = {
  actionCode: WeeklyMainActionCode;
  fixedCashDelta: number;
  energyDelta: number;
  videoViewMultiplier: number;
};

export type SponsorshipRewardRule = {
  minSubscribers: number;
  maxSubscribers: number | null;
  rewardAmount: number;
};

export type SponsorshipRewardInput =
  | {
      kind: "resolved-rule";
      rewardAmount: number;
    }
  | {
      kind: "reward-bands";
      weekStartSubscribers: number;
      rules: readonly SponsorshipRewardRule[];
    };

export type WeeklyActionState = {
  cash: number;
  energy: number;
};

export type WeeklyMainActionResult = WeeklyActionState & {
  videoViewMultiplier: number;
  sponsorshipReward: number;
};

export type ApplyWeeklyMainActionInput = {
  state: WeeklyActionState;
  actionRule: WeeklyMainActionRule;
  energyMax: number;
  sponsorshipReward?: SponsorshipRewardInput;
};

export type WeeklyEventCategory = "good" | "bad";

export type WeeklyEventCategoryRule = {
  categoryCode: WeeklyEventCategory;
  weeklyProbability: number;
};

export type WeeklyRandomEventRule = {
  code: string;
  categoryCode: WeeklyEventCategory;
  selectionWeight: number;
  weeklyViewMultiplier: number;
  fixedCashDelta: number;
  fixedSubscriberDelta: number;
  subscriberMultiplier: number;
};

export type WeeklyRandomEvent = {
  categoryCode: WeeklyEventCategory;
  rule: WeeklyRandomEventRule;
};

export type WeeklyRandomEventState = {
  cash: number;
  subscribers: number;
};

export type FlameState = {
  subscribers: number;
  energy: number;
  flameCount: number;
  weeklyViews: number;
};

export type FlameGlobalRule = {
  subscriberLossRate: number;
  energyLoss: number;
  banFlameCount: number;
};

export type FlameRollInput = {
  state: FlameState;
  weeklyProbability: number;
  globalRule: FlameGlobalRule;
  randomSource: IntegerRandomSource;
};

export type FlameRollResult = {
  occurred: boolean;
  state: FlameState;
};

export type HealthRiskRule = {
  id: string;
  minEnergy: number;
  maxEnergy: number;
  occurrenceProbability: number;
  minUnavailableWeeks: number;
  maxUnavailableWeeks: number;
};

export type HealthEvent = {
  healthRiskRuleId: string;
  durationWeeks: number;
  unavailableFromWeek: number;
  unavailableThroughWeek: number;
};

export type UnavailableWeekResult = {
  energyAfter: number;
  postedVideoCount: 0;
  mainActionApplied: false;
  randomEvent: null;
  flameOccurred: false;
  healthEvent: null;
  abilityPointsAwarded: 0;
};

export function applyWeeklyMainAction(
  input: ApplyWeeklyMainActionInput,
): WeeklyMainActionResult {
  validateWeeklyActionInput(input);

  const sponsorshipReward = resolveSponsorshipReward(
    input.actionRule.actionCode,
    input.sponsorshipReward,
  );
  const cash = addAndClampAtZero(
    input.state.cash,
    input.actionRule.fixedCashDelta,
    sponsorshipReward,
    "cash after weekly action",
  );
  const changedEnergy = addSafeIntegers(
    input.state.energy,
    input.actionRule.energyDelta,
    "energy after weekly action",
  );

  return {
    cash,
    energy:
      input.actionRule.energyDelta > 0
        ? Math.min(changedEnergy, input.energyMax)
        : changedEnergy,
    videoViewMultiplier: input.actionRule.videoViewMultiplier,
    sponsorshipReward,
  };
}

export function applyPostingEnergyCost(
  currentEnergy: number,
  postingFrequencyRule: { energyCost: number },
): number {
  requireSafeInteger(currentEnergy, "currentEnergy");
  requireNonnegativeSafeInteger(
    postingFrequencyRule.energyCost,
    "postingFrequencyRule.energyCost",
  );
  return addSafeIntegers(
    currentEnergy,
    -postingFrequencyRule.energyCost,
    "energy after posting",
  );
}

/**
 * Uses an inclusive integer draw from 1 through 1,000,000. A probability of
 * 5% therefore occurs for draws 1 through 50,000 and not for draw 50,001.
 * A zero probability returns without consuming randomness.
 */
export function rollProbability(
  probability: number,
  randomSource: IntegerRandomSource,
): boolean {
  const successfulOutcomes = probabilityToIntegerOutcomes(probability);
  if (successfulOutcomes === 0) {
    return false;
  }
  return randomSource.nextInt(1, PROBABILITY_SCALE) <= successfulOutcomes;
}

export function rollWeeklyRandomEvent(input: {
  categoryRules: readonly WeeklyEventCategoryRule[];
  eventRules: readonly WeeklyRandomEventRule[];
  randomSource: IntegerRandomSource;
}): WeeklyRandomEvent | null {
  const categoryProbabilities = validateWeeklyEventRules(
    input.categoryRules,
    input.eventRules,
  );
  const totalEventOutcomes =
    categoryProbabilities.good + categoryProbabilities.bad;
  if (totalEventOutcomes === 0) {
    return null;
  }

  const categoryDraw = input.randomSource.nextInt(1, PROBABILITY_SCALE);
  const categoryCode = resolveEventCategory(
    categoryDraw,
    categoryProbabilities,
  );
  if (categoryCode === null) {
    return null;
  }

  const matchingEvents = input.eventRules.filter(
    (eventRule) => eventRule.categoryCode === categoryCode,
  );
  return {
    categoryCode,
    rule: selectWeightedEvent(matchingEvents, input.randomSource),
  };
}

export function applyWeeklyViewEvent(
  viewsBeforeEvent: number,
  event: WeeklyRandomEvent | null,
): number {
  return calculateAdjustedWeeklyViews(
    viewsBeforeEvent,
    event?.rule.weeklyViewMultiplier ?? 1,
  );
}

export function applyWeeklyRandomEventEffect(
  state: WeeklyRandomEventState,
  event: WeeklyRandomEvent | null,
): WeeklyRandomEventState {
  requireNonnegativeSafeInteger(state.cash, "state.cash");
  requireNonnegativeSafeInteger(state.subscribers, "state.subscribers");
  if (event === null) {
    return { ...state };
  }
  validateEventRule(event.rule);

  const multipliedSubscribers = multiplyNonnegativeIntegerAndFloor(
    state.subscribers,
    event.rule.subscriberMultiplier,
  );
  return {
    cash: addAndClampAtZero(
      state.cash,
      event.rule.fixedCashDelta,
      0,
      "cash after weekly event",
    ),
    subscribers: addAndClampAtZero(
      multipliedSubscribers,
      event.rule.fixedSubscriberDelta,
      0,
      "subscribers after weekly event",
    ),
  };
}

export function rollFlameEvent(input: FlameRollInput): FlameRollResult {
  validateFlameInput(input);
  if (!rollProbability(input.weeklyProbability, input.randomSource)) {
    return { occurred: false, state: { ...input.state } };
  }

  return {
    occurred: true,
    state: {
      subscribers: multiplyNonnegativeIntegerAndFloor(
        input.state.subscribers,
        1 - input.globalRule.subscriberLossRate,
      ),
      energy: addSafeIntegers(
        input.state.energy,
        -input.globalRule.energyLoss,
        "energy after flame",
      ),
      flameCount: addSafeIntegers(
        input.state.flameCount,
        1,
        "flame count after flame",
      ),
      weeklyViews: input.state.weeklyViews,
    },
  };
}

export function rollHealthEvent(input: {
  currentWeek: number;
  energy: number;
  healthRiskRules: readonly HealthRiskRule[];
  randomSource: IntegerRandomSource;
}): HealthEvent | null {
  requirePositiveSafeInteger(input.currentWeek, "currentWeek");
  requireSafeInteger(input.energy, "energy");
  if (input.energy <= 0) {
    return null;
  }

  const healthRiskRule = resolveHealthRiskRule(
    input.energy,
    input.healthRiskRules,
  );
  if (
    !rollProbability(
      healthRiskRule.occurrenceProbability,
      input.randomSource,
    )
  ) {
    return null;
  }

  const durationWeeks = input.randomSource.nextInt(
    healthRiskRule.minUnavailableWeeks,
    healthRiskRule.maxUnavailableWeeks,
  );
  const unavailableFromWeek = addSafeIntegers(
    input.currentWeek,
    1,
    "unavailableFromWeek",
  );
  const unavailableThroughWeek = addSafeIntegers(
    unavailableFromWeek,
    durationWeeks - 1,
    "unavailableThroughWeek",
  );

  return {
    healthRiskRuleId: healthRiskRule.id,
    durationWeeks,
    unavailableFromWeek,
    unavailableThroughWeek,
  };
}

export function calculateUnavailableWeek(input: {
  energy: number;
  energyRecovery: number;
  energyMax: number;
}): UnavailableWeekResult {
  requireSafeInteger(input.energy, "energy");
  requireNonnegativeSafeInteger(input.energyRecovery, "energyRecovery");
  requirePositiveSafeInteger(input.energyMax, "energyMax");

  return {
    energyAfter: Math.min(
      addSafeIntegers(
        input.energy,
        input.energyRecovery,
        "energy after unavailable week",
      ),
      input.energyMax,
    ),
    postedVideoCount: 0,
    mainActionApplied: false,
    randomEvent: null,
    flameOccurred: false,
    healthEvent: null,
    abilityPointsAwarded: 0,
  };
}

function validateWeeklyActionInput(input: ApplyWeeklyMainActionInput): void {
  requireNonnegativeSafeInteger(input.state.cash, "state.cash");
  requireSafeInteger(input.state.energy, "state.energy");
  requirePositiveSafeInteger(input.energyMax, "energyMax");
  requireSafeInteger(
    input.actionRule.fixedCashDelta,
    "actionRule.fixedCashDelta",
  );
  requireSafeInteger(input.actionRule.energyDelta, "actionRule.energyDelta");
  requireNonnegativeFiniteNumber(
    input.actionRule.videoViewMultiplier,
    "actionRule.videoViewMultiplier",
  );
}

function resolveSponsorshipReward(
  actionCode: WeeklyMainActionCode,
  rewardInput: SponsorshipRewardInput | undefined,
): number {
  if (actionCode !== "sponsorship") {
    if (rewardInput !== undefined) {
      throw new RangeError(
        "sponsorshipReward is only valid for the sponsorship action.",
      );
    }
    return 0;
  }
  if (rewardInput === undefined) {
    throw new RangeError(
      "The sponsorship action requires a resolved reward or reward bands.",
    );
  }
  if (rewardInput.kind === "resolved-rule") {
    requireNonnegativeSafeInteger(
      rewardInput.rewardAmount,
      "sponsorship reward",
    );
    return rewardInput.rewardAmount;
  }

  requireNonnegativeSafeInteger(
    rewardInput.weekStartSubscribers,
    "weekStartSubscribers",
  );
  const matchingRules = rewardInput.rules.filter((rule) => {
    validateSponsorshipRewardRule(rule);
    return (
      rewardInput.weekStartSubscribers >= rule.minSubscribers &&
      (rule.maxSubscribers === null ||
        rewardInput.weekStartSubscribers <= rule.maxSubscribers)
    );
  });
  if (matchingRules.length !== 1) {
    throw new RangeError(
      "Exactly one sponsorship reward rule must match weekStartSubscribers.",
    );
  }
  return matchingRules[0]!.rewardAmount;
}

function validateSponsorshipRewardRule(rule: SponsorshipRewardRule): void {
  requireNonnegativeSafeInteger(rule.minSubscribers, "minimum subscribers");
  if (rule.maxSubscribers !== null) {
    requireNonnegativeSafeInteger(
      rule.maxSubscribers,
      "maximum subscribers",
    );
    if (rule.maxSubscribers < rule.minSubscribers) {
      throw new RangeError(
        "A sponsorship reward maximum must not be below its minimum.",
      );
    }
  }
  requireNonnegativeSafeInteger(rule.rewardAmount, "sponsorship reward");
}

function validateWeeklyEventRules(
  categoryRules: readonly WeeklyEventCategoryRule[],
  eventRules: readonly WeeklyRandomEventRule[],
): Record<WeeklyEventCategory, number> {
  const categoryProbabilities = new Map<WeeklyEventCategory, number>();
  for (const categoryRule of categoryRules) {
    if (categoryProbabilities.has(categoryRule.categoryCode)) {
      throw new RangeError(
        `Duplicate weekly event category: ${categoryRule.categoryCode}.`,
      );
    }
    categoryProbabilities.set(
      categoryRule.categoryCode,
      probabilityToIntegerOutcomes(categoryRule.weeklyProbability),
    );
  }
  const good = categoryProbabilities.get("good");
  const bad = categoryProbabilities.get("bad");
  if (good === undefined || bad === undefined) {
    throw new RangeError("Weekly event rules require good and bad categories.");
  }
  if (good + bad > PROBABILITY_SCALE) {
    throw new RangeError(
      "Combined weekly event probabilities must not exceed 1.",
    );
  }

  const eventCodes = new Set<string>();
  const eventCounts: Record<WeeklyEventCategory, number> = { good: 0, bad: 0 };
  for (const eventRule of eventRules) {
    validateEventRule(eventRule);
    if (eventCodes.has(eventRule.code)) {
      throw new RangeError(`Duplicate weekly event code: ${eventRule.code}.`);
    }
    eventCodes.add(eventRule.code);
    eventCounts[eventRule.categoryCode] += 1;
  }
  if (eventCounts.good === 0 || eventCounts.bad === 0) {
    throw new RangeError(
      "Weekly event rules require at least one event in each category.",
    );
  }

  return { good, bad };
}

function validateEventRule(rule: WeeklyRandomEventRule): void {
  if (rule.code.trim().length === 0) {
    throw new RangeError("Weekly event code must not be empty.");
  }
  requirePositiveSafeInteger(rule.selectionWeight, "event selection weight");
  requireNonnegativeFiniteNumber(
    rule.weeklyViewMultiplier,
    "event weekly view multiplier",
  );
  requireSafeInteger(rule.fixedCashDelta, "event fixed cash delta");
  requireSafeInteger(
    rule.fixedSubscriberDelta,
    "event fixed subscriber delta",
  );
  requireNonnegativeFiniteNumber(
    rule.subscriberMultiplier,
    "event subscriber multiplier",
  );
}

function resolveEventCategory(
  categoryDraw: number,
  probabilities: Record<WeeklyEventCategory, number>,
): WeeklyEventCategory | null {
  if (categoryDraw <= probabilities.good) {
    return "good";
  }
  if (categoryDraw <= probabilities.good + probabilities.bad) {
    return "bad";
  }
  return null;
}

function selectWeightedEvent(
  eventRules: readonly WeeklyRandomEventRule[],
  randomSource: IntegerRandomSource,
): WeeklyRandomEventRule {
  const totalWeight = eventRules.reduce(
    (sum, rule) =>
      addSafeIntegers(sum, rule.selectionWeight, "event selection weight"),
    0,
  );
  const selection = randomSource.nextInt(1, totalWeight);
  let cumulativeWeight = 0;
  for (const eventRule of eventRules) {
    cumulativeWeight = addSafeIntegers(
      cumulativeWeight,
      eventRule.selectionWeight,
      "event cumulative selection weight",
    );
    if (selection <= cumulativeWeight) {
      return eventRule;
    }
  }
  throw new RangeError("Unable to select a weekly event.");
}

function validateFlameInput(input: FlameRollInput): void {
  requireNonnegativeSafeInteger(input.state.subscribers, "state.subscribers");
  requireSafeInteger(input.state.energy, "state.energy");
  requireNonnegativeSafeInteger(input.state.flameCount, "state.flameCount");
  requireNonnegativeSafeInteger(input.state.weeklyViews, "state.weeklyViews");
  probabilityToIntegerOutcomes(input.weeklyProbability);
  probabilityToIntegerOutcomes(input.globalRule.subscriberLossRate);
  requireNonnegativeSafeInteger(
    input.globalRule.energyLoss,
    "globalRule.energyLoss",
  );
  requirePositiveSafeInteger(
    input.globalRule.banFlameCount,
    "globalRule.banFlameCount",
  );
}

function resolveHealthRiskRule(
  energy: number,
  healthRiskRules: readonly HealthRiskRule[],
): HealthRiskRule {
  const matchingRules = healthRiskRules.filter((rule) => {
    validateHealthRiskRule(rule);
    return energy >= rule.minEnergy && energy <= rule.maxEnergy;
  });
  if (matchingRules.length !== 1) {
    throw new RangeError(
      "Exactly one health risk rule must match the current energy.",
    );
  }
  return matchingRules[0]!;
}

function validateHealthRiskRule(rule: HealthRiskRule): void {
  if (rule.id.trim().length === 0) {
    throw new RangeError("Health risk rule id must not be empty.");
  }
  requirePositiveSafeInteger(rule.minEnergy, "health risk minimum energy");
  requirePositiveSafeInteger(rule.maxEnergy, "health risk maximum energy");
  if (rule.maxEnergy < rule.minEnergy) {
    throw new RangeError(
      "A health risk maximum energy must not be below its minimum.",
    );
  }
  const probabilityOutcomes = probabilityToIntegerOutcomes(
    rule.occurrenceProbability,
  );
  requireNonnegativeSafeInteger(
    rule.minUnavailableWeeks,
    "minimum unavailable weeks",
  );
  requireNonnegativeSafeInteger(
    rule.maxUnavailableWeeks,
    "maximum unavailable weeks",
  );
  if (rule.maxUnavailableWeeks < rule.minUnavailableWeeks) {
    throw new RangeError(
      "Maximum unavailable weeks must not be below the minimum.",
    );
  }
  if (probabilityOutcomes > 0 && rule.minUnavailableWeeks === 0) {
    throw new RangeError(
      "A health risk that can occur must last at least one week.",
    );
  }
}

function probabilityToIntegerOutcomes(probability: number): number {
  if (!Number.isFinite(probability) || probability < 0 || probability > 1) {
    throw new RangeError("Probability must be a finite number from 0 to 1.");
  }
  const scaledProbability = probability * PROBABILITY_SCALE;
  const integerOutcomes = Math.round(scaledProbability);
  if (Math.abs(scaledProbability - integerOutcomes) > 1e-9) {
    throw new RangeError(
      `Probability must align to the ${PROBABILITY_SCALE}-outcome scale.`,
    );
  }
  return integerOutcomes;
}

function addAndClampAtZero(
  initialValue: number,
  firstDelta: number,
  secondDelta: number,
  label: string,
): number {
  const total =
    BigInt(initialValue) + BigInt(firstDelta) + BigInt(secondDelta);
  return total <= BigInt(0) ? 0 : toSafeInteger(total, label);
}

function addSafeIntegers(left: number, right: number, label: string): number {
  requireSafeInteger(left, label);
  requireSafeInteger(right, label);
  return toSafeInteger(BigInt(left) + BigInt(right), label);
}

function toSafeInteger(value: bigint, label: string): number {
  if (
    value < BigInt(Number.MIN_SAFE_INTEGER) ||
    value > BigInt(Number.MAX_SAFE_INTEGER)
  ) {
    throw new RangeError(`${label} exceeds the safe integer range.`);
  }
  return Number(value);
}

function requireSafeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value)) {
    throw new RangeError(`${label} must be a safe integer.`);
  }
}

function requireNonnegativeSafeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${label} must be a nonnegative safe integer.`);
  }
}

function requirePositiveSafeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${label} must be a positive safe integer.`);
  }
}

function requireNonnegativeFiniteNumber(value: number, label: string): void {
  if (!Number.isFinite(value) || value < 0) {
    throw new RangeError(`${label} must be a nonnegative finite number.`);
  }
}
