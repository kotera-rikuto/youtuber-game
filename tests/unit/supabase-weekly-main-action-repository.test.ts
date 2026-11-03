import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { SelectWeeklyMainActionCommitError } from "@/backend/application/ports/weekly-main-action-repository";
import type { Json } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { SupabaseWeeklyMainActionRepository } from "@/backend/infrastructure/supabase/repositories/supabase-weekly-main-action-repository";

vi.mock("server-only", () => ({}));

const command = {
  actorUserId:
    "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"],
  runId: "00000000-0000-4000-8000-000000000002",
  action: "collaboration" as const,
  expectedVersion: 3,
};

describe("SupabaseWeeklyMainActionRepository", () => {
  it("selects the action through one atomic RPC and maps its receipt", async () => {
    const receipt: Json = {
      action: command.action,
      weekNumber: 5,
      stateVersion: 4,
    };
    const rpc = vi.fn().mockResolvedValue({ data: receipt, error: null });
    const repository = new SupabaseWeeklyMainActionRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.selectWeeklyMainAction(command)).resolves.toEqual(
      receipt,
    );
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("select_weekly_main_action", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_action: command.action,
      p_expected_version: command.expectedVersion,
    });
  });

  it.each([
    ["SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
    ["SELECT_WEEKLY_MAIN_ACTION_FORBIDDEN", "FORBIDDEN"],
    ["SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
    [
      "SELECT_WEEKLY_MAIN_ACTION_ACTIVITY_UNAVAILABLE",
      "ACTIVITY_UNAVAILABLE",
    ],
    ["SELECT_WEEKLY_MAIN_ACTION_STALE_STATE", "STALE_STATE"],
    ["SELECT_WEEKLY_MAIN_ACTION_INVALID_ACTION", "INVALID_ACTION"],
    ["SELECT_WEEKLY_MAIN_ACTION_FEATURE_LOCKED", "FEATURE_LOCKED"],
    [
      "SELECT_WEEKLY_MAIN_ACTION_ACTION_ON_COOLDOWN",
      "ACTION_ON_COOLDOWN",
    ],
    [
      "SELECT_WEEKLY_MAIN_ACTION_WEEK_ALREADY_COMMITTED",
      "WEEK_ALREADY_COMMITTED",
    ],
    ["SELECT_WEEKLY_MAIN_ACTION_COMMIT_FAILED", "COMMIT_FAILED"],
    ["unexpected database failure", "COMMIT_FAILED"],
  ] as const)("maps %s into the stable %s error", async (message, code) => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: "P0001", message },
    });
    const repository = new SupabaseWeeklyMainActionRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.selectWeeklyMainAction(command)).rejects.toMatchObject(
      {
        name: "SelectWeeklyMainActionCommitError",
        code,
      } satisfies Partial<SelectWeeklyMainActionCommitError>,
    );
  });

  it.each([
    null,
    {},
    { action: "study", weekNumber: 5, stateVersion: 4 },
    { action: "rest", weekNumber: 0, stateVersion: 4 },
    { action: "rest", weekNumber: 5, stateVersion: -1 },
  ] satisfies Json[])("rejects the malformed receipt %#", async (receipt) => {
    const rpc = vi.fn().mockResolvedValue({ data: receipt, error: null });
    const repository = new SupabaseWeeklyMainActionRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.selectWeeklyMainAction(command)).rejects.toMatchObject(
      {
        name: "SelectWeeklyMainActionCommitError",
        code: "COMMIT_FAILED",
      } satisfies Partial<SelectWeeklyMainActionCommitError>,
    );
  });
});
