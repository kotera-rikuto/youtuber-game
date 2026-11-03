import "server-only";

import type { Json } from "@/backend/infrastructure/supabase/database.types";
import {
  AdvanceWeekCommitError,
  type AdvanceWeekCommitCommand,
  type AdvanceWeekCommitReceipt,
  type AdvanceWeekCommitRepository,
  type FatalGameOverReceipt,
  type WeekCommittedReceipt,
} from "@/backend/application/ports/advance-week-commit-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseAdvanceWeekCommitRepository
  implements AdvanceWeekCommitRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async commitAdvanceWeek(
    command: AdvanceWeekCommitCommand,
  ): Promise<AdvanceWeekCommitReceipt> {
    const serializedCommand: Json = JSON.parse(JSON.stringify(command));
    const { data, error } = await this.client.rpc("commit_advance_week", {
      p_command: serializedCommand,
    });

    if (error) {
      throw mapAdvanceWeekRpcError(error.code, error.message);
    }

    return mapCommitReceipt(data);
  }
}

const advanceWeekErrorCodes = new Map<
  string,
  AdvanceWeekCommitError["code"]
>([
  ["ADVANCE_WEEK_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["ADVANCE_WEEK_FORBIDDEN", "FORBIDDEN"],
  ["ADVANCE_WEEK_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
  ["ADVANCE_WEEK_STALE_STATE", "STALE_STATE"],
  ["ADVANCE_WEEK_WEEK_ALREADY_COMMITTED", "WEEK_ALREADY_COMMITTED"],
  ["ADVANCE_WEEK_WEEKLY_ACTION_REQUIRED", "WEEKLY_ACTION_REQUIRED"],
  ["ADVANCE_WEEK_IDEMPOTENCY_KEY_REUSED", "IDEMPOTENCY_KEY_REUSED"],
  ["ADVANCE_WEEK_VALIDATION_ERROR", "VALIDATION_ERROR"],
]);

function mapAdvanceWeekRpcError(code: string, message: string) {
  if (code === "23505") {
    return new AdvanceWeekCommitError("WEEK_ALREADY_COMMITTED");
  }
  if (code === "23514" || code === "23503" || code === "22P02") {
    return new AdvanceWeekCommitError("VALIDATION_ERROR");
  }

  return new AdvanceWeekCommitError(
    advanceWeekErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}

function mapCommitReceipt(receipt: Json): AdvanceWeekCommitReceipt {
  if (!isJsonObject(receipt)) {
    throw new AdvanceWeekCommitError("COMMIT_FAILED");
  }

  if (receipt.outcome === "week_committed") {
    return mapWeekCommittedReceipt(receipt);
  }
  if (receipt.outcome === "fatal_game_over") {
    return mapFatalReceipt(receipt);
  }

  throw new AdvanceWeekCommitError("COMMIT_FAILED");
}

function mapWeekCommittedReceipt(receipt: JsonObject): WeekCommittedReceipt {
  const runStatusAfter = receipt.runStatusAfter;
  if (
    !isNonemptyString(receipt.runId) ||
    !isPositiveInteger(receipt.completedWeek) ||
    !isPositiveInteger(receipt.nextWeek) ||
    receipt.nextWeek !== receipt.completedWeek + 1 ||
    !isNonemptyString(receipt.weekResultId) ||
    !isNonnegativeInteger(receipt.nextStateVersion) ||
    !isCommittedRunStatus(runStatusAfter)
  ) {
    throw new AdvanceWeekCommitError("COMMIT_FAILED");
  }

  return {
    outcome: "week_committed",
    runId: receipt.runId,
    completedWeek: receipt.completedWeek,
    nextWeek: receipt.nextWeek,
    weekResultId: receipt.weekResultId,
    nextStateVersion: receipt.nextStateVersion,
    runStatusAfter,
  };
}

function mapFatalReceipt(receipt: JsonObject): FatalGameOverReceipt {
  if (
    !isNonemptyString(receipt.runId) ||
    !isPositiveInteger(receipt.attemptedWeek) ||
    !isNonemptyString(receipt.terminationId) ||
    (receipt.reason !== "death" && receipt.reason !== "flame_ban") ||
    receipt.runStatusAfter !== "game_over"
  ) {
    throw new AdvanceWeekCommitError("COMMIT_FAILED");
  }

  return {
    outcome: "fatal_game_over",
    runId: receipt.runId,
    attemptedWeek: receipt.attemptedWeek,
    terminationId: receipt.terminationId,
    reason: receipt.reason,
    runStatusAfter: "game_over",
  };
}

type JsonObject = { [key: string]: Json | undefined };

function isJsonObject(value: Json): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonemptyString(value: Json | undefined): value is string {
  return typeof value === "string" && value.length > 0;
}

function isPositiveInteger(value: Json | undefined): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isNonnegativeInteger(value: Json | undefined): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function isCommittedRunStatus(
  value: Json | undefined,
): value is WeekCommittedReceipt["runStatusAfter"] {
  return (
    value === "playing" ||
    value === "stage_cleared" ||
    value === "cleared" ||
    value === "game_over"
  );
}
