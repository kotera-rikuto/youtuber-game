import "server-only";

import {
  AllocateAbilityPointsCommitError,
  type AbilityAllocationRepository,
  type AllocateAbilityPointsCommand,
  type AllocateAbilityPointsCommitResult,
} from "@/backend/application/ports/ability-allocation-repository";
import type { Json } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseAbilityAllocationRepository
  implements AbilityAllocationRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async allocateAbilityPoints(
    command: AllocateAbilityPointsCommand,
  ): Promise<AllocateAbilityPointsCommitResult> {
    const allocations: Json = command.allocations;
    const { data, error } = await this.client.rpc("allocate_ability_points", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_allocations: allocations,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapAllocateAbilityPointsRpcError(error.code, error.message);
    }
    if (
      typeof data !== "number" ||
      !Number.isSafeInteger(data) ||
      data !== command.expectedVersion + 1
    ) {
      throw new AllocateAbilityPointsCommitError("COMMIT_FAILED");
    }

    return { nextStateVersion: data };
  }
}

const allocationErrorCodes = new Map<
  string,
  AllocateAbilityPointsCommitError["code"]
>([
  ["ALLOCATE_ABILITY_POINTS_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["ALLOCATE_ABILITY_POINTS_FORBIDDEN", "FORBIDDEN"],
  ["ALLOCATE_ABILITY_POINTS_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
  ["ALLOCATE_ABILITY_POINTS_ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
  ["ALLOCATE_ABILITY_POINTS_STALE_STATE", "STALE_STATE"],
  ["ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION", "INVALID_ALLOCATION"],
  [
    "ALLOCATE_ABILITY_POINTS_INSUFFICIENT_ABILITY_POINTS",
    "INSUFFICIENT_ABILITY_POINTS",
  ],
  ["ALLOCATE_ABILITY_POINTS_ABILITY_LIMIT_EXCEEDED", "ABILITY_LIMIT_EXCEEDED"],
]);

function mapAllocateAbilityPointsRpcError(
  code: string,
  message: string,
): AllocateAbilityPointsCommitError {
  if (code === "23514" || code === "23503" || code === "22P02") {
    return new AllocateAbilityPointsCommitError("INVALID_ALLOCATION");
  }

  return new AllocateAbilityPointsCommitError(
    allocationErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}
