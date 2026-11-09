import type { UseCaseContext } from "@/backend/application/auth/authentication";

export type AbandonGameCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  expectedVersion: number;
};

export type RenameChannelCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  channelName: string;
  expectedVersion: number;
};

export type GameRunManagementCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_ACTIVE"
  | "STALE_STATE"
  | "INVALID_CHANNEL_NAME"
  | "ALREADY_ABANDONED"
  | "COMMIT_FAILED";

export class GameRunManagementCommitError extends Error {
  constructor(readonly code: GameRunManagementCommitErrorCode) {
    super("The game run management operation could not be committed.");
    this.name = "GameRunManagementCommitError";
  }
}

export type AbandonGameCommitResult = {
  occurredWeek: number;
};

export type RenameChannelCommitResult = {
  channelName: string;
  nextStateVersion: number;
};

export interface GameRunManagementRepository {
  abandonGame(
    command: AbandonGameCommand,
  ): Promise<AbandonGameCommitResult>;
  renameChannel(
    command: RenameChannelCommand,
  ): Promise<RenameChannelCommitResult>;
}