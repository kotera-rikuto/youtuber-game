import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  GameRunManagementCommitError,
  type GameRunManagementRepository,
} from "@/backend/application/ports/game-run-management-repository";
import { normalizeChannelName } from "@/backend/domain/game/channel-name";

export type RenameChannelInput = {
  runId: string;
  channelName: string;
  expectedVersion: number;
};

export type RenameChannelResult = {
  channelName: string;
  nextStateVersion: number;
};

export type RenameChannelErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_ACTIVE"
  | "STALE_STATE"
  | "INVALID_CHANNEL_NAME"
  | "COMMIT_FAILED";

export class RenameChannelError extends Error {
  constructor(readonly code: RenameChannelErrorCode) {
    super("チャンネル名を変更できませんでした。");
    this.name = "RenameChannelError";
  }
}

export type RenameChannelDependencies = {
  gameRuns: GameRunManagementRepository;
};

export async function renameChannel(
  context: UseCaseContext,
  input: RenameChannelInput,
  dependencies: RenameChannelDependencies,
): Promise<RenameChannelResult> {
  const channelName = normalizeChannelName(input.channelName);
  if (
    channelName === null ||
    typeof input.runId !== "string" ||
    input.runId.length === 0 ||
    !Number.isInteger(input.expectedVersion) ||
    input.expectedVersion < 0
  ) {
    throw new RenameChannelError("INVALID_CHANNEL_NAME");
  }

  try {
    return await dependencies.gameRuns.renameChannel({
      actorUserId: context.actorUserId,
      runId: input.runId,
      channelName,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof GameRunManagementCommitError) {
      throw new RenameChannelError(mapRenameErrorCode(error.code));
    }
    throw error;
  }
}

function mapRenameErrorCode(
  code: GameRunManagementCommitError["code"],
): RenameChannelErrorCode {
  return code === "ALREADY_ABANDONED" ? "COMMIT_FAILED" : code;
}