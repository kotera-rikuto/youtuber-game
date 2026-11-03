import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  IdeaStockManagementCommitError,
  type IdeaStockManagementCommitErrorCode,
  type IdeaStockManagementRepository,
} from "@/backend/application/ports/idea-stock-management-repository";

export type ReorderIdeaStockInput = {
  runId: string;
  orderedIdeaIds: string[];
  expectedVersion: number;
};

export type ReorderIdeaStockErrorCode = Exclude<
  IdeaStockManagementCommitErrorCode,
  "IDEA_NOT_FOUND" | "IDEA_ALREADY_POSTED" | "IDEA_ALREADY_DELETED"
>;

export class ReorderIdeaStockError extends Error {
  constructor(readonly code: ReorderIdeaStockErrorCode) {
    super("企画ストックを並び替えできませんでした。");
    this.name = "ReorderIdeaStockError";
  }
}

export type ReorderIdeaStockDependencies = {
  ideas: IdeaStockManagementRepository;
};

export async function reorderIdeaStock(
  context: UseCaseContext,
  input: ReorderIdeaStockInput,
  dependencies: ReorderIdeaStockDependencies,
): Promise<void> {
  if (new Set(input.orderedIdeaIds).size !== input.orderedIdeaIds.length) {
    throw new ReorderIdeaStockError("INVALID_IDEA_ORDER");
  }

  try {
    await dependencies.ideas.reorderIdeaStock({
      actorUserId: context.actorUserId,
      runId: input.runId,
      orderedIdeaIds: input.orderedIdeaIds,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof IdeaStockManagementCommitError) {
      throw new ReorderIdeaStockError(mapCommitError(error.code));
    }
    throw error;
  }
}

function mapCommitError(
  code: IdeaStockManagementCommitErrorCode,
): ReorderIdeaStockErrorCode {
  if (
    code === "IDEA_NOT_FOUND" ||
    code === "IDEA_ALREADY_POSTED" ||
    code === "IDEA_ALREADY_DELETED"
  ) {
    return "COMMIT_FAILED";
  }
  return code;
}
