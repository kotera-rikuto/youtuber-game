import "server-only";

import {
  GameRunManagementCommitError,
  type AbandonGameCommand,
  type AbandonGameCommitResult,
  type GameRunManagementRepository,
  type RenameChannelCommand,
  type RenameChannelCommitResult,
} from "@/backend/application/ports/game-run-management-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseGameRunManagementRepository
  implements GameRunManagementRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async abandonGame(
    command: AbandonGameCommand,
  ): Promise<AbandonGameCommitResult> {
    const { data, error } = await this.client.rpc("abandon_game", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapRpcError(error.message);
    }
    if (!isAbandonReceipt(data)) {
      throw new GameRunManagementCommitError("COMMIT_FAILED");
    }

    return { occurredWeek: data.occurredWeek };
  }

  async renameChannel(
    command: RenameChannelCommand,
  ): Promise<RenameChannelCommitResult> {
    const { data, error } = await this.client.rpc("rename_channel", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_channel_name: command.channelName,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapRpcError(error.message);
    }
    if (!isRenameReceipt(data)) {
      throw new GameRunManagementCommitError("COMMIT_FAILED");
    }

    return {
      channelName: data.channelName,
      nextStateVersion: data.nextStateVersion,
    };
  }
}

function mapRpcError(message: string): GameRunManagementCommitError {
  const code = message.match(/^(?:ABANDON_GAME|RENAME_CHANNEL)_(.+)$/)?.[1];
  const stableCodes = new Set([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_ACTIVE",
    "STALE_STATE",
    "INVALID_CHANNEL_NAME",
    "ALREADY_ABANDONED",
  ]);

  return new GameRunManagementCommitError(
    code && stableCodes.has(code)
      ? (code as GameRunManagementCommitError["code"])
      : "COMMIT_FAILED",
  );
}

function isAbandonReceipt(
  value: unknown,
): value is { occurredWeek: number } {
  const occurredWeek =
    typeof value === "object" && value !== null && "occurredWeek" in value
      ? value.occurredWeek
      : null;

  return (
    typeof occurredWeek === "number" &&
    Number.isInteger(occurredWeek) &&
    occurredWeek >= 1
  );
}

function isRenameReceipt(
  value: unknown,
): value is { channelName: string; nextStateVersion: number } {
  const channelName =
    typeof value === "object" && value !== null && "channelName" in value
      ? value.channelName
      : null;
  const nextStateVersion =
    typeof value === "object" && value !== null && "nextStateVersion" in value
      ? value.nextStateVersion
      : null;

  return (
    typeof channelName === "string" &&
    channelName.length > 0 &&
    typeof nextStateVersion === "number" &&
    Number.isInteger(nextStateVersion) &&
    nextStateVersion >= 1
  );
}