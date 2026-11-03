import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { IdeaEvaluationResult } from "@/backend/application/ports/idea-evaluator";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { GameRunStatus } from "@/backend/domain/game/game-run";
import type { IdeaTitle } from "@/backend/domain/game/idea-creation";

export type CreateIdeaRunLookup =
  | { status: "not_found" }
  | { status: "forbidden" }
  | {
      status: "found";
      runStatus: GameRunStatus;
      currentWeek: number;
      stateVersion: number;
      channelType: string;
      specialty: string | null;
    };

export type CreateIdeaCapacityQuery = OwnedRunQuery & {
  weekNumber: number;
};

export type CreateIdeaCapacity = {
  ideasCreatedThisWeek: number;
  pendingIdeaCount: number;
  ideasPerWeekLimit: number;
  ideaStockLimit: number;
  isActivityUnavailable: boolean;
};

export type CommitCreateIdeaCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  expectedVersion: number;
  title: IdeaTitle;
  description: string | null;
  evaluation: IdeaEvaluationResult;
};

export type CommitCreateIdeaResult = {
  ideaId: string;
};

export type CommitCreateIdeaErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "STALE_STATE"
  | "ACTIVITY_UNAVAILABLE"
  | "IDEA_WEEKLY_LIMIT"
  | "IDEA_STOCK_FULL"
  | "VALIDATION_ERROR"
  | "COMMIT_FAILED";

export class CommitCreateIdeaError extends Error {
  constructor(readonly code: CommitCreateIdeaErrorCode) {
    super("The idea could not be created.");
    this.name = "CommitCreateIdeaError";
  }
}

export interface CreateIdeaRepository {
  findRun(query: OwnedRunQuery): Promise<CreateIdeaRunLookup>;
  getCapacity(
    query: CreateIdeaCapacityQuery,
  ): Promise<CreateIdeaCapacity | null>;
  commitCreateIdea(
    command: CommitCreateIdeaCommand,
  ): Promise<CommitCreateIdeaResult>;
}
