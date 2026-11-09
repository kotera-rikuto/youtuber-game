import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  GameRunManagementCommitError,
  type GameRunManagementRepository,
} from "@/backend/application/ports/game-run-management-repository";

export type AbandonGameInput = {
  runId: string;
  expectedVersion: number;
};

export type AbandonGameResult = {
  occurredWeek: number;
};

export type AbandonGameErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_ACTIVE"
  | "STALE_STATE"
  | "ALREADY_ABANDONED"
  | "COMMIT_FAILED";

export class AbandonGameError extends Error {
  constructor(readonly code: AbandonGameErrorCode) {
    super("ゲームを中断できませんでした。");
    this.name = "AbandonGameError";
  }
}

export type AbandonGameDependencies = {
  gameRuns: GameRunManagementRepository;
};

export async function abandonGame(
  context: UseCaseContext,
  input: AbandonGameInput,
  dependencies: AbandonGameDependencies,
): Promise<AbandonGameResult> {
  if (
    typeof input.runId !== "string" ||
    input.runId.length === 0 ||
    !Number.isInteger(input.expectedVersion) ||
    input.expectedVersion < 0
  ) {
    throw new AbandonGameError("COMMIT_FAILED");
  }

  try {
    return await dependencies.gameRuns.abandonGame({
      actorUserId: context.actorUserId,
      runId: input.runId,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof GameRunManagementCommitError) {
      throw new AbandonGameError(mapAbandonErrorCode(error.code));
    }
    throw error;
  }
}

function mapAbandonErrorCode(
  code: GameRunManagementCommitError["code"],
): AbandonGameErrorCode {
  return code === "INVALID_CHANNEL_NAME" ? "COMMIT_FAILED" : code;
}