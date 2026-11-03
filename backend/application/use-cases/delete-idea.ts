import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  IdeaStockManagementCommitError,
  type IdeaStockManagementCommitErrorCode,
  type IdeaStockManagementRepository,
} from "@/backend/application/ports/idea-stock-management-repository";

export type DeleteIdeaInput = {
  runId: string;
  ideaId: string;
  expectedVersion: number;
};

export type DeleteIdeaErrorCode = Exclude<
  IdeaStockManagementCommitErrorCode,
  "INVALID_IDEA_ORDER"
>;

export class DeleteIdeaError extends Error {
  constructor(readonly code: DeleteIdeaErrorCode) {
    super("企画を削除できませんでした。");
    this.name = "DeleteIdeaError";
  }
}

export type DeleteIdeaDependencies = {
  ideas: IdeaStockManagementRepository;
};

export async function deleteIdea(
  context: UseCaseContext,
  input: DeleteIdeaInput,
  dependencies: DeleteIdeaDependencies,
): Promise<void> {
  try {
    await dependencies.ideas.deleteIdea({
      actorUserId: context.actorUserId,
      runId: input.runId,
      ideaId: input.ideaId,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof IdeaStockManagementCommitError) {
      throw new DeleteIdeaError(
        error.code === "INVALID_IDEA_ORDER" ? "COMMIT_FAILED" : error.code,
      );
    }
    throw error;
  }
}
