import "server-only";

import {
  IdeaStockManagementCommitError,
  type DeleteIdeaCommand,
  type IdeaStockManagementCommitErrorCode,
  type IdeaStockManagementRepository,
  type ReorderIdeaStockCommand,
} from "@/backend/application/ports/idea-stock-management-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseIdeaStockManagementRepository
  implements IdeaStockManagementRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async deleteIdea(command: DeleteIdeaCommand): Promise<void> {
    const { data, error } = await this.client.rpc("delete_idea", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_idea_id: command.ideaId,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapIdeaStockManagementRpcError(error.message, "DELETE_IDEA");
    }
    assertNextVersion(data, command.expectedVersion);
  }

  async reorderIdeaStock(command: ReorderIdeaStockCommand): Promise<void> {
    const { data, error } = await this.client.rpc("reorder_idea_stock", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_ordered_idea_ids: [...command.orderedIdeaIds],
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapIdeaStockManagementRpcError(
        error.message,
        "REORDER_IDEA_STOCK",
      );
    }
    assertNextVersion(data, command.expectedVersion);
  }
}

function assertNextVersion(data: number, expectedVersion: number): void {
  if (!Number.isInteger(data) || data !== expectedVersion + 1) {
    throw new IdeaStockManagementCommitError("COMMIT_FAILED");
  }
}

const rpcErrorCodes = new Map<string, IdeaStockManagementCommitErrorCode>([
  ["RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["FORBIDDEN", "FORBIDDEN"],
  ["RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
  ["ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
  ["STALE_STATE", "STALE_STATE"],
  ["IDEA_NOT_FOUND", "IDEA_NOT_FOUND"],
  ["IDEA_ALREADY_POSTED", "IDEA_ALREADY_POSTED"],
  ["IDEA_ALREADY_DELETED", "IDEA_ALREADY_DELETED"],
  ["INVALID_IDEA_ORDER", "INVALID_IDEA_ORDER"],
]);

function mapIdeaStockManagementRpcError(
  message: string,
  operation: "DELETE_IDEA" | "REORDER_IDEA_STOCK",
): IdeaStockManagementCommitError {
  const prefix = `${operation}_`;
  const unprefixedCode = message.startsWith(prefix)
    ? message.slice(prefix.length)
    : "";
  return new IdeaStockManagementCommitError(
    rpcErrorCodes.get(unprefixedCode) ?? "COMMIT_FAILED",
  );
}
