const EQUIPMENT_SLOT_COUNT = 3;
const MAX_EQUIPMENT_MULTIPLIER = 1.45;
const MAX_ABILITY_VALUE = 100;
const MIN_IDEA_SCORE = 0;
const MAX_IDEA_SCORE = 100;
const BIGINT_ZERO = BigInt(0);
const BIGINT_ONE = BigInt(1);
const BIGINT_TEN = BigInt(10);
const BIGINT_NEGATIVE_ONE = BigInt(-1);

type Fraction = {
  numerator: bigint;
  denominator: bigint;
};

export type AbilityValue = {
  code: string;
  value: number;
};

export type AbilityWeight = {
  abilityCode: string;
  weight: number;
};

export type IdeaScoreBand = {
  minScore: number;
  maxScore: number;
  viewMultiplier: number;
  subscriberConversionRate: number;
};

export type SystemIdeaRule = {
  viewMultiplier: number;
  subscriberConversionRate: number;
};

export type VideoIdea =
  | { source: "player"; score: number }
  | { source: "system" };

export type VideoSimulationInput = {
  videoId: string;
  sequenceNumber: number;
  baseViews: number;
  idea: VideoIdea;
};

export type SimulateVideosInput = {
  videos: readonly VideoSimulationInput[];
  baseViewsRange: {
    min: number;
    max: number;
  };
  currentSubscribers: number;
  abilities: readonly AbilityValue[];
  abilityWeights: readonly AbilityWeight[];
  ideaScoreBands: readonly IdeaScoreBand[];
  systemIdeaRule: SystemIdeaRule;
  postingFrequencyMultiplier: number;
  channelMultiplier: number;
  equipmentViewBonuses: readonly number[];
  collaborationMultiplier: number;
};

export type SimulatedVideo = {
  videoId: string;
  sequenceNumber: number;
  baseViews: number;
  subscriberMultiplier: number;
  abilityMultiplier: number;
  ideaMultiplier: number;
  postingFrequencyMultiplier: number;
  channelMultiplier: number;
  equipmentMultiplier: number;
  collaborationMultiplier: number;
  viewsBeforeEvent: number;
  subscriberConversionRate: number;
};

export type ViewAllocationInput = {
  videoId: string;
  sequenceNumber: number;
  viewsBeforeEvent: number;
};

export type ViewAllocation = ViewAllocationInput & {
  finalViews: number;
};

export type AdjustedViewAllocation = {
  eventMultiplier: number;
  viewsBeforeEvent: number;
  finalViews: number;
  videos: readonly ViewAllocation[];
};

export type SubscriberChangeInput = {
  videoId: string;
  finalViews: number;
  subscriberConversionRate: number;
};

export type VideoSubscriberChange = SubscriberChangeInput & {
  subscribersGained: number;
};

export type SubscriberChanges = {
  totalSubscribersGained: number;
  videos: readonly VideoSubscriberChange[];
};

export type WeeklyVideoCalculationInput = SimulateVideosInput & {
  weeklyEventMultiplier: number;
  isAdRevenueAvailable: boolean;
  adRevenuePerView: number;
};

export type VideoCalculationResult = SimulatedVideo & {
  weeklyEventMultiplier: number;
  finalViews: number;
  subscribersGained: number;
};

export type WeeklyVideoCalculationResult = {
  viewsBeforeEvent: number;
  finalViews: number;
  totalSubscribersGained: number;
  adRevenue: number;
  videos: readonly VideoCalculationResult[];
};

export function multiplyNonnegativeIntegerAndFloor(
  value: number,
  multiplier: number,
): number {
  return floorProductToSafeInteger(
    value,
    [multiplier],
    "multiplied nonnegative integer",
  );
}

export function calculateAdjustedWeeklyViews(
  viewsBeforeEvent: number,
  eventMultiplier: number,
): number {
  return multiplyNonnegativeIntegerAndFloor(
    viewsBeforeEvent,
    eventMultiplier,
  );
}

export function calculateSubscriberMultiplier(
  currentSubscribers: number,
): number {
  requireNonnegativeSafeInteger(currentSubscribers, "currentSubscribers");
  return 1 + Math.floor(currentSubscribers / 100_000) * 0.5;
}

export function calculateAbilityMultiplier(
  abilities: readonly AbilityValue[],
  abilityWeights: readonly AbilityWeight[],
): number {
  if (abilityWeights.length !== 2) {
    throw new RangeError("abilityWeights must contain exactly two entries.");
  }

  const abilityValues = new Map<string, number>();
  for (const ability of abilities) {
    requireNonemptyString(ability.code, "ability code");
    requireIntegerInRange(
      ability.value,
      0,
      MAX_ABILITY_VALUE,
      `ability ${ability.code}`,
    );
    if (abilityValues.has(ability.code)) {
      throw new RangeError(`Duplicate ability code: ${ability.code}.`);
    }
    abilityValues.set(ability.code, ability.value);
  }

  const weightedAbility = abilityWeights.reduce<Fraction>(
    (total, rule) => {
      requireNonemptyString(rule.abilityCode, "ability weight code");
      const abilityValue = abilityValues.get(rule.abilityCode);
      if (abilityValue === undefined) {
        throw new RangeError(`Missing ability value: ${rule.abilityCode}.`);
      }
      requirePositiveFiniteNumber(
        rule.weight,
        `ability weight ${rule.abilityCode}`,
      );
      return addFractions(
        total,
        multiplyFractions(
          fractionFromSafeInteger(abilityValue),
          fractionFromNumber(rule.weight),
        ),
      );
    },
    fractionFromSafeInteger(0),
  );

  const seenWeightCodes = new Set(
    abilityWeights.map((rule) => rule.abilityCode),
  );
  if (seenWeightCodes.size !== abilityWeights.length) {
    throw new RangeError("abilityWeights contains a duplicate ability code.");
  }

  const weightTotal = abilityWeights.reduce<Fraction>(
    (total, rule) => addFractions(total, fractionFromNumber(rule.weight)),
    fractionFromSafeInteger(0),
  );
  if (!fractionsEqual(weightTotal, fractionFromSafeInteger(1))) {
    throw new RangeError("abilityWeights must total exactly 1.");
  }

  return fractionToFiniteNumber(
    addFractions(
      fractionFromSafeInteger(1),
      divideFractionBySafeInteger(
        addFractions(weightedAbility, fractionFromSafeInteger(-10)),
        100,
      ),
    ),
    "ability multiplier",
  );
}

export function calculateEquipmentMultiplier(
  equipmentViewBonuses: readonly number[],
): number {
  if (equipmentViewBonuses.length !== EQUIPMENT_SLOT_COUNT) {
    throw new RangeError(
      `equipmentViewBonuses must contain ${EQUIPMENT_SLOT_COUNT} entries.`,
    );
  }

  const totalBonus = equipmentViewBonuses.reduce<Fraction>((total, bonus) => {
    requireNonnegativeFiniteNumber(bonus, "equipment view bonus");
    return addFractions(total, fractionFromNumber(bonus));
  }, fractionFromSafeInteger(0));
  const uncappedMultiplier = addFractions(
    fractionFromSafeInteger(1),
    totalBonus,
  );
  const maximumMultiplier = fractionFromNumber(MAX_EQUIPMENT_MULTIPLIER);

  return fractionToFiniteNumber(
    compareFractions(uncappedMultiplier, maximumMultiplier) > 0
      ? maximumMultiplier
      : uncappedMultiplier,
    "equipment multiplier",
  );
}

export function resolveIdeaCalculation(
  idea: VideoIdea,
  ideaScoreBands: readonly IdeaScoreBand[],
  systemIdeaRule: SystemIdeaRule,
): Pick<SimulatedVideo, "ideaMultiplier" | "subscriberConversionRate"> {
  validateIdeaRules(ideaScoreBands, systemIdeaRule);

  if (idea.source === "system") {
    return {
      ideaMultiplier: systemIdeaRule.viewMultiplier,
      subscriberConversionRate: systemIdeaRule.subscriberConversionRate,
    };
  }

  requireIntegerInRange(
    idea.score,
    MIN_IDEA_SCORE,
    MAX_IDEA_SCORE,
    "idea score",
  );
  const matchingBand = ideaScoreBands.find(
    (band) => idea.score >= band.minScore && idea.score <= band.maxScore,
  );
  if (matchingBand === undefined) {
    throw new RangeError(`No idea score band contains score ${idea.score}.`);
  }

  return {
    ideaMultiplier: matchingBand.viewMultiplier,
    subscriberConversionRate: matchingBand.subscriberConversionRate,
  };
}

export function simulateVideos(input: SimulateVideosInput): readonly SimulatedVideo[] {
  validateBaseViewsRange(input.baseViewsRange);
  validateVideoIdentityAndSequence(input.videos);
  validateMultiplier(
    input.postingFrequencyMultiplier,
    "postingFrequencyMultiplier",
  );
  validateMultiplier(input.channelMultiplier, "channelMultiplier");
  validateMultiplier(
    input.collaborationMultiplier,
    "collaborationMultiplier",
  );

  const subscriberMultiplier = calculateSubscriberMultiplier(
    input.currentSubscribers,
  );
  const abilityMultiplier = calculateAbilityMultiplier(
    input.abilities,
    input.abilityWeights,
  );
  const equipmentMultiplier = calculateEquipmentMultiplier(
    input.equipmentViewBonuses,
  );

  return input.videos.map((video) => {
    requireIntegerInRange(
      video.baseViews,
      input.baseViewsRange.min,
      input.baseViewsRange.max,
      `base views for ${video.videoId}`,
    );
    const ideaCalculation = resolveIdeaCalculation(
      video.idea,
      input.ideaScoreBands,
      input.systemIdeaRule,
    );
    const viewsBeforeEvent = floorProductToSafeInteger(
      video.baseViews,
      [
        subscriberMultiplier,
        abilityMultiplier,
        ideaCalculation.ideaMultiplier,
        input.postingFrequencyMultiplier,
        input.channelMultiplier,
        equipmentMultiplier,
        input.collaborationMultiplier,
      ],
      `views before event for ${video.videoId}`,
    );

    return {
      videoId: video.videoId,
      sequenceNumber: video.sequenceNumber,
      baseViews: video.baseViews,
      subscriberMultiplier,
      abilityMultiplier,
      ideaMultiplier: ideaCalculation.ideaMultiplier,
      postingFrequencyMultiplier: input.postingFrequencyMultiplier,
      channelMultiplier: input.channelMultiplier,
      equipmentMultiplier,
      collaborationMultiplier: input.collaborationMultiplier,
      viewsBeforeEvent,
      subscriberConversionRate:
        ideaCalculation.subscriberConversionRate,
    };
  });
}

export function allocateAdjustedViewsToVideos(
  videos: readonly ViewAllocationInput[],
  eventMultiplier: number,
): AdjustedViewAllocation {
  validateVideoIdentityAndSequence(videos);
  validateMultiplier(eventMultiplier, "eventMultiplier");

  let viewsBeforeEvent = 0;
  for (const video of videos) {
    requireNonnegativeSafeInteger(
      video.viewsBeforeEvent,
      `views before event for ${video.videoId}`,
    );
    viewsBeforeEvent = addSafeIntegers(
      viewsBeforeEvent,
      video.viewsBeforeEvent,
      "weekly views before event",
    );
  }

  const finalViews = calculateAdjustedWeeklyViews(
    viewsBeforeEvent,
    eventMultiplier,
  );
  if (viewsBeforeEvent === 0) {
    return {
      eventMultiplier,
      viewsBeforeEvent,
      finalViews,
      videos: videos.map((video) => ({ ...video, finalViews: 0 })),
    };
  }

  const denominator = BigInt(viewsBeforeEvent);
  const allocations = videos.map((video, inputIndex) => {
    const exactNumerator = BigInt(finalViews) * BigInt(video.viewsBeforeEvent);
    return {
      inputIndex,
      sequenceNumber: video.sequenceNumber,
      quotient: exactNumerator / denominator,
      remainder: exactNumerator % denominator,
    };
  });
  const allocatedFloorTotal = allocations.reduce(
    (total, allocation) => total + allocation.quotient,
    BIGINT_ZERO,
  );
  const remainingViews = Number(BigInt(finalViews) - allocatedFloorTotal);
  const remainderPriority = [...allocations].sort((left, right) => {
    if (left.remainder !== right.remainder) {
      return left.remainder > right.remainder ? -1 : 1;
    }
    return left.sequenceNumber - right.sequenceNumber;
  });
  const receivesRemainder = new Set(
    remainderPriority
      .slice(0, remainingViews)
      .map((allocation) => allocation.inputIndex),
  );

  return {
    eventMultiplier,
    viewsBeforeEvent,
    finalViews,
    videos: videos.map((video, inputIndex) => ({
      ...video,
      finalViews: toSafeInteger(
        allocations[inputIndex]!.quotient +
          (receivesRemainder.has(inputIndex) ? BIGINT_ONE : BIGINT_ZERO),
        `allocated views for ${video.videoId}`,
      ),
    })),
  };
}

export function calculateSubscriberChanges(
  videos: readonly SubscriberChangeInput[],
): SubscriberChanges {
  const seenVideoIds = new Set<string>();
  let totalSubscribersGained = 0;
  const changes = videos.map((video) => {
    requireUniqueVideoId(video.videoId, seenVideoIds);
    requireNonnegativeSafeInteger(
      video.finalViews,
      `final views for ${video.videoId}`,
    );
    validateConversionRate(
      video.subscriberConversionRate,
      `subscriber conversion rate for ${video.videoId}`,
    );
    const subscribersGained = floorProductToSafeInteger(
      video.finalViews,
      [video.subscriberConversionRate],
      `subscribers gained for ${video.videoId}`,
    );
    totalSubscribersGained = addSafeIntegers(
      totalSubscribersGained,
      subscribersGained,
      "weekly subscribers gained",
    );

    return { ...video, subscribersGained };
  });

  return { totalSubscribersGained, videos: changes };
}

export function calculateAdRevenue(
  finalWeeklyViews: number,
  adRevenuePerView: number,
  isAdRevenueAvailable: boolean,
): number {
  requireNonnegativeSafeInteger(finalWeeklyViews, "finalWeeklyViews");
  requireNonnegativeFiniteNumber(adRevenuePerView, "adRevenuePerView");
  if (!isAdRevenueAvailable) {
    return 0;
  }
  return floorProductToSafeInteger(
    finalWeeklyViews,
    [adRevenuePerView],
    "ad revenue",
  );
}

export function calculateWeeklyVideoResult(
  input: WeeklyVideoCalculationInput,
): WeeklyVideoCalculationResult {
  const simulatedVideos = simulateVideos(input);
  const allocation = allocateAdjustedViewsToVideos(
    simulatedVideos,
    input.weeklyEventMultiplier,
  );
  const subscriberChanges = calculateSubscriberChanges(
    allocation.videos.map((video, index) => ({
      videoId: video.videoId,
      finalViews: video.finalViews,
      subscriberConversionRate:
        simulatedVideos[index]!.subscriberConversionRate,
    })),
  );
  const adRevenue = calculateAdRevenue(
    allocation.finalViews,
    input.adRevenuePerView,
    input.isAdRevenueAvailable,
  );

  return {
    viewsBeforeEvent: allocation.viewsBeforeEvent,
    finalViews: allocation.finalViews,
    totalSubscribersGained: subscriberChanges.totalSubscribersGained,
    adRevenue,
    videos: simulatedVideos.map((video, index) => ({
      ...video,
      weeklyEventMultiplier: allocation.eventMultiplier,
      finalViews: allocation.videos[index]!.finalViews,
      subscribersGained: subscriberChanges.videos[index]!.subscribersGained,
    })),
  };
}

function validateBaseViewsRange(range: { min: number; max: number }): void {
  requireNonnegativeSafeInteger(range.min, "baseViewsRange.min");
  requireNonnegativeSafeInteger(range.max, "baseViewsRange.max");
  if (range.min > range.max) {
    throw new RangeError("baseViewsRange.min must not exceed max.");
  }
}

function validateVideoIdentityAndSequence(
  videos: readonly { videoId: string; sequenceNumber: number }[],
): void {
  const videoIds = new Set<string>();
  const sequenceNumbers = new Set<number>();
  for (const video of videos) {
    requireUniqueVideoId(video.videoId, videoIds);
    requirePositiveSafeInteger(
      video.sequenceNumber,
      `sequence number for ${video.videoId}`,
    );
    if (sequenceNumbers.has(video.sequenceNumber)) {
      throw new RangeError(
        `Duplicate video sequence number: ${video.sequenceNumber}.`,
      );
    }
    sequenceNumbers.add(video.sequenceNumber);
  }
}

function requireUniqueVideoId(videoId: string, seenIds: Set<string>): void {
  requireNonemptyString(videoId, "videoId");
  if (seenIds.has(videoId)) {
    throw new RangeError(`Duplicate videoId: ${videoId}.`);
  }
  seenIds.add(videoId);
}

function validateIdeaRules(
  ideaScoreBands: readonly IdeaScoreBand[],
  systemIdeaRule: SystemIdeaRule,
): void {
  validateMultiplier(systemIdeaRule.viewMultiplier, "system idea multiplier");
  validateConversionRate(
    systemIdeaRule.subscriberConversionRate,
    "system idea subscriber conversion rate",
  );
  if (ideaScoreBands.length === 0) {
    throw new RangeError("ideaScoreBands must not be empty.");
  }

  const orderedBands = [...ideaScoreBands].sort(
    (left, right) => left.minScore - right.minScore,
  );
  let expectedMinimum = MIN_IDEA_SCORE;
  for (const band of orderedBands) {
    requireIntegerInRange(
      band.minScore,
      MIN_IDEA_SCORE,
      MAX_IDEA_SCORE,
      "idea band minimum",
    );
    requireIntegerInRange(
      band.maxScore,
      MIN_IDEA_SCORE,
      MAX_IDEA_SCORE,
      "idea band maximum",
    );
    if (band.minScore !== expectedMinimum || band.maxScore < band.minScore) {
      throw new RangeError(
        "ideaScoreBands must cover scores 0 through 100 without gaps or overlaps.",
      );
    }
    validateMultiplier(band.viewMultiplier, "idea band multiplier");
    validateConversionRate(
      band.subscriberConversionRate,
      "idea band subscriber conversion rate",
    );
    expectedMinimum = band.maxScore + 1;
  }
  if (expectedMinimum !== MAX_IDEA_SCORE + 1) {
    throw new RangeError(
      "ideaScoreBands must cover scores 0 through 100 without gaps or overlaps.",
    );
  }
}

function validateMultiplier(multiplier: number, label: string): void {
  requireNonnegativeFiniteNumber(multiplier, label);
}

function validateConversionRate(rate: number, label: string): void {
  requireNonnegativeFiniteNumber(rate, label);
  if (rate > 1) {
    throw new RangeError(`${label} must not exceed 1.`);
  }
}

function requireNonemptyString(value: string, label: string): void {
  if (value.trim().length === 0) {
    throw new RangeError(`${label} must not be empty.`);
  }
}

function requireIntegerInRange(
  value: number,
  minimum: number,
  maximum: number,
  label: string,
): void {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(
      `${label} must be a safe integer from ${minimum} through ${maximum}.`,
    );
  }
}

function requirePositiveSafeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${label} must be a positive safe integer.`);
  }
}

function requireNonnegativeSafeInteger(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${label} must be a nonnegative safe integer.`);
  }
}

function requirePositiveFiniteNumber(value: number, label: string): void {
  if (!Number.isFinite(value) || value <= 0) {
    throw new RangeError(`${label} must be a positive finite number.`);
  }
}

function requireNonnegativeFiniteNumber(value: number, label: string): void {
  if (!Number.isFinite(value) || value < 0) {
    throw new RangeError(`${label} must be a nonnegative finite number.`);
  }
}

function floorProductToSafeInteger(
  integer: number,
  factors: readonly number[],
  label: string,
): number {
  requireNonnegativeSafeInteger(integer, label);
  const product = factors.reduce<Fraction>((current, factor) => {
    requireNonnegativeFiniteNumber(factor, `${label} factor`);
    return multiplyFractions(current, fractionFromNumber(factor));
  }, fractionFromSafeInteger(integer));
  return toSafeInteger(product.numerator / product.denominator, label);
}

function addSafeIntegers(left: number, right: number, label: string): number {
  return toSafeInteger(BigInt(left) + BigInt(right), label);
}

function toSafeInteger(value: bigint, label: string): number {
  if (value < BIGINT_ZERO || value > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new RangeError(`${label} exceeds the nonnegative safe integer range.`);
  }
  return Number(value);
}

function fractionFromSafeInteger(value: number): Fraction {
  if (!Number.isSafeInteger(value)) {
    throw new RangeError("Cannot convert a non-safe integer to a fraction.");
  }
  return { numerator: BigInt(value), denominator: BIGINT_ONE };
}

function fractionFromNumber(value: number): Fraction {
  if (!Number.isFinite(value)) {
    throw new RangeError("Cannot convert a non-finite number to a fraction.");
  }
  const match = value
    .toString()
    .match(/^(-?)(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/i);
  if (match === null) {
    throw new RangeError(`Cannot convert ${value} to a decimal fraction.`);
  }

  const sign = match[1] === "-" ? BIGINT_NEGATIVE_ONE : BIGINT_ONE;
  const integerDigits = match[2]!;
  const fractionalDigits = match[3] ?? "";
  const exponent = Number(match[4] ?? 0);
  const digits = BigInt(`${integerDigits}${fractionalDigits}`);
  const decimalPlaces = fractionalDigits.length - exponent;
  const fraction =
    decimalPlaces >= 0
      ? {
          numerator: sign * digits,
          denominator: BIGINT_TEN ** BigInt(decimalPlaces),
        }
      : {
          numerator: sign * digits * BIGINT_TEN ** BigInt(-decimalPlaces),
          denominator: BIGINT_ONE,
        };
  return reduceFraction(fraction);
}

function addFractions(left: Fraction, right: Fraction): Fraction {
  return reduceFraction({
    numerator:
      left.numerator * right.denominator +
      right.numerator * left.denominator,
    denominator: left.denominator * right.denominator,
  });
}

function multiplyFractions(left: Fraction, right: Fraction): Fraction {
  return reduceFraction({
    numerator: left.numerator * right.numerator,
    denominator: left.denominator * right.denominator,
  });
}

function divideFractionBySafeInteger(
  fraction: Fraction,
  divisor: number,
): Fraction {
  if (!Number.isSafeInteger(divisor) || divisor === 0) {
    throw new RangeError("Fraction divisor must be a nonzero safe integer.");
  }
  return reduceFraction({
    numerator: fraction.numerator,
    denominator: fraction.denominator * BigInt(divisor),
  });
}

function fractionsEqual(left: Fraction, right: Fraction): boolean {
  return (
    left.numerator * right.denominator ===
    right.numerator * left.denominator
  );
}

function compareFractions(left: Fraction, right: Fraction): number {
  const difference =
    left.numerator * right.denominator -
    right.numerator * left.denominator;
  return difference === BIGINT_ZERO
    ? 0
    : difference > BIGINT_ZERO
      ? 1
      : -1;
}

function fractionToFiniteNumber(fraction: Fraction, label: string): number {
  const value = Number(fraction.numerator) / Number(fraction.denominator);
  if (!Number.isFinite(value)) {
    throw new RangeError(`${label} cannot be represented as a finite number.`);
  }
  return value;
}

function reduceFraction(fraction: Fraction): Fraction {
  if (fraction.denominator === BIGINT_ZERO) {
    throw new RangeError("Fraction denominator must not be zero.");
  }
  if (fraction.numerator === BIGINT_ZERO) {
    return { numerator: BIGINT_ZERO, denominator: BIGINT_ONE };
  }
  const sign =
    fraction.denominator < BIGINT_ZERO ? BIGINT_NEGATIVE_ONE : BIGINT_ONE;
  const numerator = fraction.numerator * sign;
  const denominator = fraction.denominator * sign;
  const divisor = greatestCommonDivisor(
    numerator < BIGINT_ZERO ? -numerator : numerator,
    denominator,
  );
  return {
    numerator: numerator / divisor,
    denominator: denominator / divisor,
  };
}

function greatestCommonDivisor(left: bigint, right: bigint): bigint {
  let currentLeft = left;
  let currentRight = right;
  while (currentRight !== BIGINT_ZERO) {
    const remainder = currentLeft % currentRight;
    currentLeft = currentRight;
    currentRight = remainder;
  }
  return currentLeft;
}
