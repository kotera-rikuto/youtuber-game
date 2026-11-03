import type { UseCaseContext } from "@/backend/application/auth/authentication";

export type AdvanceWeekCommonCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  attemptedWeek: number;
  expectedVersion: number;
  idempotencyKey: string;
};

export type WeekResultSnapshot = {
  viewsBeforeEvent: number;
  finalViews: number;
  subscribersBefore: number;
  maxSubscribersDuringWeek: number;
  subscribersAfter: number;
  energyBefore: number;
  energyAfter: number;
  cashBefore: number;
  cashAfter: number;
  adRevenue: number;
  flameCountAfter: number;
};

export type RunStateAfterWeek = {
  cash: number;
  energy: number;
  subscribers: number;
  cumulativeViews: number;
  flameCount: number;
};

export type VideoCalculationSnapshot = {
  baseViews: number;
  subscriberMultiplier: number;
  abilityMultiplier: number;
  ideaMultiplier: number;
  postingFrequencyMultiplier: number;
  channelMultiplier: number;
  equipmentMultiplier: number;
  collaborationMultiplier: number;
  viewsBeforeEvent: number;
  eventMultiplier: number;
  finalViews: number;
  conversionRate: number;
  subscribersGained: number;
};

type CommittedVideoBase = {
  sequenceNumber: number;
  titleSnapshot: string;
  calculation: VideoCalculationSnapshot;
};

export type CommittedVideo =
  | (CommittedVideoBase & {
      source: "player";
      playerIdeaId: string;
    })
  | (CommittedVideoBase & {
      source: "system";
      systemIdeaCycleEntryId: string;
    });

export type RandomEventCommit = {
  kind: "random";
  eventRuleId: string;
  cashBefore: number;
  cashAfter: number;
  subscribersBefore: number;
  subscribersAfter: number;
};

export type FlameEventCommit = {
  kind: "flame";
  subscribersBefore: number;
  subscribersAfter: number;
  energyBefore: number;
  energyAfter: number;
  flameCountBefore: number;
  flameCountAfter: number;
};

export type CommittedEvent = RandomEventCommit | FlameEventCommit;

export type GoalCommitOutcome = "active" | "achieved" | "deadline";

export type HealthConditionCommit = {
  healthRiskRuleId: string;
  durationWeeks: number;
};

export type NormalWeekCommitCommand = AdvanceWeekCommonCommand & {
  kind: "normal";
  weeklyActionId: string;
  postingFrequencyRuleId: string;
  weekResult: WeekResultSnapshot;
  stateAfter: RunStateAfterWeek;
  videos: readonly CommittedVideo[];
  events: readonly CommittedEvent[];
  featureUnlockRuleIds: readonly string[];
  healthCondition: HealthConditionCommit | null;
  abilityPointsAwarded: number;
  abilityPointGrantStatus: "available" | "held";
  goalOutcome: GoalCommitOutcome;
};

export type ActivityUnavailableWeekCommitCommand = AdvanceWeekCommonCommand & {
  kind: "activity_unavailable";
  weekResult: WeekResultSnapshot;
  stateAfter: RunStateAfterWeek;
  goalOutcome: GoalCommitOutcome;
};

export type FatalAdvanceWeekCommitCommand = AdvanceWeekCommonCommand & {
  kind: "fatal_game_over";
  reason: "death" | "flame_ban";
  calculatedEnergy: number;
  calculatedFlameCount: number;
};

export type AdvanceWeekCommitCommand =
  | NormalWeekCommitCommand
  | ActivityUnavailableWeekCommitCommand
  | FatalAdvanceWeekCommitCommand;

export type WeekCommittedReceipt = {
  outcome: "week_committed";
  runId: string;
  completedWeek: number;
  nextWeek: number;
  weekResultId: string;
  nextStateVersion: number;
  runStatusAfter: "playing" | "stage_cleared" | "cleared" | "game_over";
};

export type FatalGameOverReceipt = {
  outcome: "fatal_game_over";
  runId: string;
  attemptedWeek: number;
  terminationId: string;
  reason: "death" | "flame_ban";
  runStatusAfter: "game_over";
};

export type AdvanceWeekCommitReceipt =
  | WeekCommittedReceipt
  | FatalGameOverReceipt;

export type AdvanceWeekCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "STALE_STATE"
  | "WEEK_ALREADY_COMMITTED"
  | "WEEKLY_ACTION_REQUIRED"
  | "IDEMPOTENCY_KEY_REUSED"
  | "VALIDATION_ERROR"
  | "COMMIT_FAILED";

export class AdvanceWeekCommitError extends Error {
  constructor(readonly code: AdvanceWeekCommitErrorCode) {
    super("The weekly result could not be committed.");
    this.name = "AdvanceWeekCommitError";
  }
}

export interface AdvanceWeekCommitRepository {
  commitAdvanceWeek(
    command: AdvanceWeekCommitCommand,
  ): Promise<AdvanceWeekCommitReceipt>;
}
