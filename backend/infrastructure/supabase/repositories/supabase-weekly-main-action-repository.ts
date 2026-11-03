import "server-only";

import {
  SelectWeeklyMainActionCommitError,
  WEEKLY_MAIN_ACTIONS,
  type SelectWeeklyMainActionCommand,
  type SelectWeeklyMainActionReceipt,
  type WeeklyMainAction,
  type WeeklyMainActionRepository,
} from "@/backend/application/ports/weekly-main-action-repository";
import type { Json } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseWeeklyMainActionRepository
  implements WeeklyMainActionRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async selectWeeklyMainAction(
    command: SelectWeeklyMainActionCommand,
  ): Promise<SelectWeeklyMainActionReceipt> {
    const { data, error } = await this.client.rpc("select_weekly_main_action", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_action: command.action,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapSelectWeeklyMainActionRpcError(error.message);
    }

    return mapReceipt(data);
  }
}

const selectWeeklyMainActionErrorCodes = new Map<
  string,
  SelectWeeklyMainActionCommitError["code"]
>([
  ["SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["SELECT_WEEKLY_MAIN_ACTION_FORBIDDEN", "FORBIDDEN"],
  ["SELECT_WEEKLY_MAIN_ACTION_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
  ["SELECT_WEEKLY_MAIN_ACTION_ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
  ["SELECT_WEEKLY_MAIN_ACTION_STALE_STATE", "STALE_STATE"],
  ["SELECT_WEEKLY_MAIN_ACTION_INVALID_ACTION", "INVALID_ACTION"],
  ["SELECT_WEEKLY_MAIN_ACTION_FEATURE_LOCKED", "FEATURE_LOCKED"],
  ["SELECT_WEEKLY_MAIN_ACTION_ACTION_ON_COOLDOWN", "ACTION_ON_COOLDOWN"],
  ["SELECT_WEEKLY_MAIN_ACTION_WEEK_ALREADY_COMMITTED", "WEEK_ALREADY_COMMITTED"],
]);

function mapSelectWeeklyMainActionRpcError(
  message: string,
): SelectWeeklyMainActionCommitError {
  return new SelectWeeklyMainActionCommitError(
    selectWeeklyMainActionErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}

function mapReceipt(receipt: Json): SelectWeeklyMainActionReceipt {
  if (
    !isJsonObject(receipt) ||
    !isWeeklyMainAction(receipt.action) ||
    !isPositiveInteger(receipt.weekNumber) ||
    !isNonnegativeInteger(receipt.stateVersion)
  ) {
    throw new SelectWeeklyMainActionCommitError("COMMIT_FAILED");
  }

  return {
    action: receipt.action,
    weekNumber: receipt.weekNumber,
    stateVersion: receipt.stateVersion,
  };
}

type JsonObject = { [key: string]: Json | undefined };

function isJsonObject(value: Json): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isWeeklyMainAction(
  value: Json | undefined,
): value is WeeklyMainAction {
  return (
    typeof value === "string" &&
    (WEEKLY_MAIN_ACTIONS as readonly string[]).includes(value)
  );
}

function isPositiveInteger(value: Json | undefined): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isNonnegativeInteger(value: Json | undefined): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}
