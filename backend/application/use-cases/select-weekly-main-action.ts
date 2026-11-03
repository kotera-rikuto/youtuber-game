import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  SelectWeeklyMainActionCommitError,
  WEEKLY_MAIN_ACTIONS,
  type SelectWeeklyMainActionCommitErrorCode,
  type SelectWeeklyMainActionReceipt,
  type WeeklyMainAction,
  type WeeklyMainActionRepository,
} from "@/backend/application/ports/weekly-main-action-repository";

export type { WeeklyMainAction };

export type SelectWeeklyMainActionInput = {
  runId: string;
  action: WeeklyMainAction;
  expectedVersion: number;
};

export type SelectWeeklyMainActionResult = SelectWeeklyMainActionReceipt;

export type SelectWeeklyMainActionErrorCode =
  SelectWeeklyMainActionCommitErrorCode;

export class SelectWeeklyMainActionError extends Error {
  constructor(readonly code: SelectWeeklyMainActionErrorCode) {
    super("週間メイン行動を選択できませんでした。");
    this.name = "SelectWeeklyMainActionError";
  }
}

export type SelectWeeklyMainActionDependencies = {
  weeklyMainActions: WeeklyMainActionRepository;
};

const weeklyMainActionValues: ReadonlySet<string> = new Set(
  WEEKLY_MAIN_ACTIONS,
);

export async function selectWeeklyMainAction(
  context: UseCaseContext,
  input: SelectWeeklyMainActionInput,
  dependencies: SelectWeeklyMainActionDependencies,
): Promise<SelectWeeklyMainActionResult> {
  if (!weeklyMainActionValues.has(input.action)) {
    throw new SelectWeeklyMainActionError("INVALID_ACTION");
  }

  try {
    return await dependencies.weeklyMainActions.selectWeeklyMainAction({
      actorUserId: context.actorUserId,
      runId: input.runId,
      action: input.action,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof SelectWeeklyMainActionCommitError) {
      throw new SelectWeeklyMainActionError(error.code);
    }
    throw error;
  }
}
