import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type {
  SystemIdeaCycle,
  SystemIdeaPoolCandidate,
} from "@/backend/domain/game/system-idea-cycle";

export type CommitSystemIdeaCycleCommand = OwnedRunQuery & {
  requiredCount: number;
  orderedRuleSetSystemIdeaIds: readonly string[];
};

export type CommitSystemIdeaCycleErrorCode =
  | "RUN_NOT_FOUND"
  | "POOL_INVALID"
  | "CYCLE_CONFLICT"
  | "COMMIT_FAILED";

export class CommitSystemIdeaCycleError extends Error {
  constructor(readonly code: CommitSystemIdeaCycleErrorCode) {
    super("The system idea cycle could not be committed.");
    this.name = "CommitSystemIdeaCycleError";
  }
}

export interface SystemIdeaRepository {
  findPool(
    query: OwnedRunQuery,
  ): Promise<readonly SystemIdeaPoolCandidate[] | null>;
  listCycles(query: OwnedRunQuery): Promise<readonly SystemIdeaCycle[] | null>;
  commitCycle(command: CommitSystemIdeaCycleCommand): Promise<{ cycleId: string }>;
}
