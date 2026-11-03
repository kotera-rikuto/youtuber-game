import type { UseCaseContext } from "@/backend/application/auth/authentication";

export type AbilityPointAllocations = {
  planning: number;
  talking: number;
  expertise: number;
  editing: number;
  visual: number;
  filming: number;
};

export type AllocateAbilityPointsCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  allocations: AbilityPointAllocations;
  expectedVersion: number;
};

export type AllocateAbilityPointsCommitResult = {
  nextStateVersion: number;
};

export type AllocateAbilityPointsCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "INVALID_ALLOCATION"
  | "INSUFFICIENT_ABILITY_POINTS"
  | "ABILITY_LIMIT_EXCEEDED"
  | "COMMIT_FAILED";

export class AllocateAbilityPointsCommitError extends Error {
  constructor(readonly code: AllocateAbilityPointsCommitErrorCode) {
    super("The ability points could not be allocated.");
    this.name = "AllocateAbilityPointsCommitError";
  }
}

export interface AbilityAllocationRepository {
  allocateAbilityPoints(
    command: AllocateAbilityPointsCommand,
  ): Promise<AllocateAbilityPointsCommitResult>;
}
