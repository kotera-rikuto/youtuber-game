import type { UseCaseContext } from "@/backend/application/auth/authentication";

export type DeleteIdeaCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  ideaId: string;
  expectedVersion: number;
};

export type ReorderIdeaStockCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  orderedIdeaIds: readonly string[];
  expectedVersion: number;
};

export type IdeaStockManagementCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "IDEA_NOT_FOUND"
  | "IDEA_ALREADY_POSTED"
  | "IDEA_ALREADY_DELETED"
  | "INVALID_IDEA_ORDER"
  | "COMMIT_FAILED";

export class IdeaStockManagementCommitError extends Error {
  constructor(readonly code: IdeaStockManagementCommitErrorCode) {
    super("The idea stock could not be changed.");
    this.name = "IdeaStockManagementCommitError";
  }
}

export interface IdeaStockManagementRepository {
  deleteIdea(command: DeleteIdeaCommand): Promise<void>;
  reorderIdeaStock(command: ReorderIdeaStockCommand): Promise<void>;
}
