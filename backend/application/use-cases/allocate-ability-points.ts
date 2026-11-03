import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  AllocateAbilityPointsCommitError,
  type AbilityAllocationRepository,
  type AbilityPointAllocations,
} from "@/backend/application/ports/ability-allocation-repository";

export type AllocateAbilityPointsInput = AbilityPointAllocations & {
  runId: string;
  expectedVersion: number;
};

export type AllocateAbilityPointsResult = {
  nextStateVersion: number;
};

export type AllocateAbilityPointsErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "INVALID_ALLOCATION"
  | "INSUFFICIENT_ABILITY_POINTS"
  | "ABILITY_LIMIT_EXCEEDED"
  | "COMMIT_FAILED";

export class AllocateAbilityPointsError extends Error {
  constructor(readonly code: AllocateAbilityPointsErrorCode) {
    super("能力ポイントを割り振れませんでした。");
    this.name = "AllocateAbilityPointsError";
  }
}

export type AllocateAbilityPointsDependencies = {
  abilityAllocations: AbilityAllocationRepository;
};

const inputKeys = new Set([
  "runId",
  "planning",
  "talking",
  "expertise",
  "editing",
  "visual",
  "filming",
  "expectedVersion",
]);
const POSTGRES_INTEGER_MAX = 2_147_483_647;

export async function allocateAbilityPoints(
  context: UseCaseContext,
  input: AllocateAbilityPointsInput,
  dependencies: AllocateAbilityPointsDependencies,
): Promise<AllocateAbilityPointsResult> {
  if (
    typeof input !== "object" ||
    input === null ||
    typeof input.runId !== "string" ||
    input.runId.length === 0 ||
    !Number.isSafeInteger(input.expectedVersion) ||
    input.expectedVersion < 0 ||
    input.expectedVersion > POSTGRES_INTEGER_MAX
  ) {
    throw new AllocateAbilityPointsError("INVALID_ALLOCATION");
  }

  const command = {
    actorUserId: context.actorUserId,
    runId: input.runId,
    allocations: validateAllocations(input),
    expectedVersion: input.expectedVersion,
  };

  try {
    return await dependencies.abilityAllocations.allocateAbilityPoints(command);
  } catch (error) {
    if (error instanceof AllocateAbilityPointsCommitError) {
      throw new AllocateAbilityPointsError(error.code);
    }
    throw error;
  }
}

function validateAllocations(
  input: AllocateAbilityPointsInput,
): AbilityPointAllocations {
  if (
    typeof input !== "object" ||
    input === null ||
    Object.keys(input).some((key) => !inputKeys.has(key))
  ) {
    throw new AllocateAbilityPointsError("INVALID_ALLOCATION");
  }

  const allocations: AbilityPointAllocations = {
    planning: input.planning,
    talking: input.talking,
    expertise: input.expertise,
    editing: input.editing,
    visual: input.visual,
    filming: input.filming,
  };

  if (
    Object.values(allocations).some(
      (points) => !Number.isSafeInteger(points) || points < 0,
    )
  ) {
    throw new AllocateAbilityPointsError("INVALID_ALLOCATION");
  }

  return allocations;
}
