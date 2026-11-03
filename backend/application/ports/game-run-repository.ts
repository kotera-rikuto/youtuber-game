import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { GameRun } from "@/backend/domain/game/game-run";
import type {
  PostingStyle,
  SpecialtyCode,
} from "@/backend/domain/game/rules";

export type StartGameCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  channelName: string;
  postingStyle: PostingStyle;
  specialtyCode: SpecialtyCode | null;
};

export type StartGameCommitResult = {
  runId: string;
};

export type StartGameCommitErrorCode =
  | "ACTIVE_GAME_EXISTS"
  | "RULES_UNAVAILABLE"
  | "SPECIALTY_REQUIRED"
  | "SPECIALTY_NOT_ALLOWED"
  | "VALIDATION_ERROR"
  | "COMMIT_FAILED";

export class StartGameCommitError extends Error {
  constructor(readonly code: StartGameCommitErrorCode) {
    super("The game could not be started.");
    this.name = "StartGameCommitError";
  }
}

export interface GameRunRepository {
  findActiveByOwner(
    actorUserId: UseCaseContext["actorUserId"],
  ): Promise<GameRun | null>;
  findCurrentById(query: OwnedRunQuery): Promise<GameRun | null>;
  commitStartGame(command: StartGameCommand): Promise<StartGameCommitResult>;
}
