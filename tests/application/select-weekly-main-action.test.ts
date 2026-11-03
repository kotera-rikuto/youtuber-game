import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  SelectWeeklyMainActionCommitError,
  WEEKLY_MAIN_ACTIONS,
  type SelectWeeklyMainActionCommitErrorCode,
  type WeeklyMainActionRepository,
} from "@/backend/application/ports/weekly-main-action-repository";
import {
  selectWeeklyMainAction,
  type SelectWeeklyMainActionInput,
} from "@/backend/application/use-cases/select-weekly-main-action";

const context: UseCaseContext = {
  actorUserId:
    "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"],
};

const input: SelectWeeklyMainActionInput = {
  runId: "00000000-0000-4000-8000-000000000002",
  action: "part_time_job",
  expectedVersion: 4,
};

describe("selectWeeklyMainAction", () => {
  it.each(WEEKLY_MAIN_ACTIONS)("selects the %s action", async (action) => {
    const selectAction = vi.fn().mockResolvedValue({
      action,
      weekNumber: 7,
      stateVersion: 5,
    });
    const weeklyMainActions = {
      selectWeeklyMainAction: selectAction,
    } satisfies WeeklyMainActionRepository;

    await expect(
      selectWeeklyMainAction(
        context,
        { ...input, action },
        { weeklyMainActions },
      ),
    ).resolves.toEqual({ action, weekNumber: 7, stateVersion: 5 });
    expect(selectAction).toHaveBeenCalledWith({
      actorUserId: context.actorUserId,
      runId: input.runId,
      action,
      expectedVersion: input.expectedVersion,
    });
  });

  it("rejects an action outside the four supported choices before persistence", async () => {
    const selectAction = vi.fn();
    const weeklyMainActions = {
      selectWeeklyMainAction: selectAction,
    } satisfies WeeklyMainActionRepository;

    await expect(
      selectWeeklyMainAction(
        context,
        { ...input, action: "study" as SelectWeeklyMainActionInput["action"] },
        { weeklyMainActions },
      ),
    ).rejects.toMatchObject({
      name: "SelectWeeklyMainActionError",
      code: "INVALID_ACTION",
    });
    expect(selectAction).not.toHaveBeenCalled();
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_PLAYABLE",
    "ACTIVITY_UNAVAILABLE",
    "STALE_STATE",
    "INVALID_ACTION",
    "FEATURE_LOCKED",
    "ACTION_ON_COOLDOWN",
    "WEEK_ALREADY_COMMITTED",
    "COMMIT_FAILED",
  ] satisfies readonly SelectWeeklyMainActionCommitErrorCode[])(
    "preserves the repository %s error contract",
    async (code) => {
      const weeklyMainActions: WeeklyMainActionRepository = {
        selectWeeklyMainAction: vi
          .fn()
          .mockRejectedValue(new SelectWeeklyMainActionCommitError(code)),
      };

      await expect(
        selectWeeklyMainAction(context, input, { weeklyMainActions }),
      ).rejects.toMatchObject({
        name: "SelectWeeklyMainActionError",
        code,
      });
    },
  );
});
