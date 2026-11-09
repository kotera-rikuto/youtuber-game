export type AbilityPointGrantStatus =
  | "available"
  | "held"
  | "expired"
  | "consumed";

export type AbilityPointGrantSnapshot = {
  grantId: string;
  status: AbilityPointGrantStatus;
  remainingPoints: number;
};

export type ReplaceAbilityPointsInput = {
  weekKind: "normal" | "activity_unavailable";
  healthConditionStarted: boolean;
  currentWeek: number;
  abilityPointsAwarded: number;
  newPointsAvailableFromWeek: number;
  existingGrants: readonly AbilityPointGrantSnapshot[];
};

export type ReplacedAbilityPoints = {
  outcome: "replaced";
  expiredGrantIds: readonly string[];
  newGrant: {
    earnedWeek: number;
    availableFromWeek: number;
    amount: number;
    status: "available" | "held";
  };
};

export type HeldAbilityPoints = {
  outcome: "held";
  expiredGrantIds: readonly [];
  newGrant: null;
  retainedGrantIds: readonly string[];
};

export type ReplaceAbilityPointsResult =
  | ReplacedAbilityPoints
  | HeldAbilityPoints;

export type FeatureUnlockRule = {
  id: string;
  featureCode: string;
  unlockSubscribers: number;
  activationDelayWeeks: number;
};

export type FeatureUnlockCheckInput = {
  currentWeek: number;
  maxSubscribersDuringWeek: number;
  featureRules: readonly FeatureUnlockRule[];
  unlockedFeatureRuleIds: readonly string[];
};

export type FeatureUnlock = {
  featureRuleId: string;
  featureCode: string;
  unlockedWeek: number;
  activeFromWeek: number;
};

export type FeatureUnlockCheckResult = {
  outcome: "checked";
  unlocks: readonly FeatureUnlock[];
};

export type StageGoalRule = {
  targetSubscribers: number;
  startedWeek: number;
  deadlineWeek: number;
  isFinal: boolean;
};

export type StageGoalCheckInput = {
  currentWeek: number;
  subscribers: number;
  goalRule: StageGoalRule;
};

export type StageGoalCheckResult =
  | { outcome: "active" }
  | { outcome: "stage_cleared" }
  | { outcome: "cleared" }
  | { outcome: "deadline" };

export type GameOverCheckInput = {
  flameCount: number;
  energy: number;
  banFlameCount: number;
  stageGoalOutcome: StageGoalCheckResult["outcome"];
};

export type GameOverCheckResult = {
  outcome: "continue" | "flame_ban" | "death" | "deadline";
  calculatedEnergy: number;
  calculatedFlameCount: number;
};

export function replaceAbilityPointsForNextWeek(
  input: ReplaceAbilityPointsInput,
): ReplaceAbilityPointsResult {
  validateReplaceAbilityPointsInput(input);

  const activeGrantIds = input.existingGrants
    .filter(
      (grant) =>
        (grant.status === "available" || grant.status === "held") &&
        grant.remainingPoints > 0,
    )
    .map((grant) => grant.grantId);

  if (input.weekKind === "activity_unavailable") {
    return {
      outcome: "held",
      expiredGrantIds: [],
      newGrant: null,
      retainedGrantIds: activeGrantIds,
    };
  }

  return {
    outcome: "replaced",
    expiredGrantIds: activeGrantIds,
    newGrant: {
      earnedWeek: input.currentWeek,
      availableFromWeek: input.newPointsAvailableFromWeek,
      amount: input.abilityPointsAwarded,
      status: input.healthConditionStarted ? "held" : "available",
    },
  };
}

export function checkFeatureUnlocks(
  input: FeatureUnlockCheckInput,
): FeatureUnlockCheckResult {
  validateFeatureUnlockCheckInput(input);
  const unlockedRuleIds = new Set(input.unlockedFeatureRuleIds);
  const unlocks: FeatureUnlock[] = [];

  for (const rule of input.featureRules) {
    if (
      !unlockedRuleIds.has(rule.id) &&
      input.maxSubscribersDuringWeek >= rule.unlockSubscribers
    ) {
      unlocks.push({
        featureRuleId: rule.id,
        featureCode: rule.featureCode,
        unlockedWeek: input.currentWeek,
        activeFromWeek: addSafeIntegers(
          input.currentWeek,
          rule.activationDelayWeeks,
          "activeFromWeek",
        ),
      });
    }
  }

  return { outcome: "checked", unlocks };
}

export function checkStageGoal(
  input: StageGoalCheckInput,
): StageGoalCheckResult {
  validateStageGoalCheckInput(input);
  if (input.subscribers >= input.goalRule.targetSubscribers) {
    return { outcome: input.goalRule.isFinal ? "cleared" : "stage_cleared" };
  }
  if (input.currentWeek >= input.goalRule.deadlineWeek) {
    return { outcome: "deadline" };
  }
  return { outcome: "active" };
}

export function checkGameOver(
  input: GameOverCheckInput,
): GameOverCheckResult {
  validateGameOverCheckInput(input);
  if (input.flameCount >= input.banFlameCount) {
    return {
      outcome: "flame_ban",
      calculatedEnergy: input.energy,
      calculatedFlameCount: input.flameCount,
    };
  }
  if (input.energy <= 0) {
    return {
      outcome: "death",
      calculatedEnergy: input.energy,
      calculatedFlameCount: input.flameCount,
    };
  }
  if (input.stageGoalOutcome === "deadline") {
    return {
      outcome: "deadline",
      calculatedEnergy: input.energy,
      calculatedFlameCount: input.flameCount,
    };
  }
  return {
    outcome: "continue",
    calculatedEnergy: input.energy,
    calculatedFlameCount: input.flameCount,
  };
}

function validateReplaceAbilityPointsInput(
  input: ReplaceAbilityPointsInput,
): void {
  requirePositiveSafeInteger(input.currentWeek, "currentWeek");
  requireNonnegativeSafeInteger(
    input.abilityPointsAwarded,
    "abilityPointsAwarded",
  );
  requirePositiveSafeInteger(
    input.newPointsAvailableFromWeek,
    "newPointsAvailableFromWeek",
  );
  const expectedAvailableFromWeek = addSafeIntegers(
    input.currentWeek,
    1,
    "newPointsAvailableFromWeek",
  );
  if (input.newPointsAvailableFromWeek !== expectedAvailableFromWeek) {
    throw new RangeError(
      "New ability points must become available in the following week.",
    );
  }
  const grantIds = new Set<string>();
  for (const grant of input.existingGrants) {
    if (grant.grantId.trim().length === 0 || grantIds.has(grant.grantId)) {
      throw new RangeError("Ability point grant IDs must be unique and non-empty.");
    }
    grantIds.add(grant.grantId);
    requireNonnegativeSafeInteger(
      grant.remainingPoints,
      "ability grant remainingPoints",
    );
  }
}

function validateFeatureUnlockCheckInput(input: FeatureUnlockCheckInput): void {
  requirePositiveSafeInteger(input.currentWeek, "currentWeek");
  requireNonnegativeSafeInteger(
    input.maxSubscribersDuringWeek,
    "maxSubscribersDuringWeek",
  );
  const ruleIds = new Set<string>();
  const featureCodes = new Set<string>();
  for (const rule of input.featureRules) {
    if (
      rule.id.trim().length === 0 ||
      rule.featureCode.trim().length === 0 ||
      ruleIds.has(rule.id) ||
      featureCodes.has(rule.featureCode)
    ) {
      throw new RangeError("Feature rules must have unique IDs and feature codes.");
    }
    ruleIds.add(rule.id);
    featureCodes.add(rule.featureCode);
    requireNonnegativeSafeInteger(rule.unlockSubscribers, "unlockSubscribers");
    requireNonnegativeSafeInteger(
      rule.activationDelayWeeks,
      "activationDelayWeeks",
    );
  }
  const unlockedIds = new Set<string>();
  for (const ruleId of input.unlockedFeatureRuleIds) {
    if (ruleId.trim().length === 0 || unlockedIds.has(ruleId)) {
      throw new RangeError("Unlocked feature rule IDs must be unique and non-empty.");
    }
    unlockedIds.add(ruleId);
  }
}

function validateStageGoalCheckInput(input: StageGoalCheckInput): void {
  requirePositiveSafeInteger(input.currentWeek, "currentWeek");
  requireNonnegativeSafeInteger(input.subscribers, "subscribers");
  requirePositiveSafeInteger(
    input.goalRule.targetSubscribers,
    "targetSubscribers",
  );
  requirePositiveSafeInteger(input.goalRule.startedWeek, "startedWeek");
  requirePositiveSafeInteger(input.goalRule.deadlineWeek, "deadlineWeek");
  if (input.goalRule.deadlineWeek < input.goalRule.startedWeek) {
    throw new RangeError("deadlineWeek must not precede startedWeek.");
  }
  if (input.currentWeek < input.goalRule.startedWeek) {
    throw new RangeError("currentWeek must not precede startedWeek.");
  }
}

function validateGameOverCheckInput(input: GameOverCheckInput): void {
  requireNonnegativeSafeInteger(input.flameCount, "flameCount");
  requireSafeInteger(input.energy, "energy");
  requirePositiveSafeInteger(input.banFlameCount, "banFlameCount");
  if (
    input.stageGoalOutcome !== "active" &&
    input.stageGoalOutcome !== "stage_cleared" &&
    input.stageGoalOutcome !== "cleared" &&
    input.stageGoalOutcome !== "deadline"
  ) {
    throw new RangeError("Unknown stage goal outcome.");
  }
}

function addSafeIntegers(left: number, right: number, label: string): number {
  const sum = BigInt(left) + BigInt(right);
  if (
    sum < BigInt(Number.MIN_SAFE_INTEGER) ||
    sum > BigInt(Number.MAX_SAFE_INTEGER)
  ) {
    throw new RangeError(`${label} exceeds the safe integer range.`);
  }
  return Number(sum);
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
