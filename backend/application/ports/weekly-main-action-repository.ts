import type { UseCaseContext } from "@/backend/application/auth/authentication";

export const WEEKLY_MAIN_ACTIONS = [
  "part_time_job",
  "rest",
  "collaboration",
  "sponsorship",
] as const;

export type WeeklyMainAction = (typeof WEEKLY_MAIN_ACTIONS)[number];

export type SelectWeeklyMainActionCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  action: WeeklyMainAction;
  expectedVersion: number;
};

export type SelectWeeklyMainActionReceipt = {
  action: WeeklyMainAction;
  weekNumber: number;
  stateVersion: number;
};

export type SelectWeeklyMainActionCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "INVALID_ACTION"
  | "FEATURE_LOCKED"
  | "ACTION_ON_COOLDOWN"
  | "WEEK_ALREADY_COMMITTED"
  | "COMMIT_FAILED";

export class SelectWeeklyMainActionCommitError extends Error {
  constructor(readonly code: SelectWeeklyMainActionCommitErrorCode) {
    super("The weekly main action could not be selected.");
    this.name = "SelectWeeklyMainActionCommitError";
  }
}

export interface WeeklyMainActionRepository {
  selectWeeklyMainAction(
    command: SelectWeeklyMainActionCommand,
  ): Promise<SelectWeeklyMainActionReceipt>;
}
