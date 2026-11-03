import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  CommitCreateIdeaError,
  type CreateIdeaRepository,
  type CreateIdeaRunLookup,
} from "@/backend/application/ports/create-idea-repository";
import type { IdeaEvaluator } from "@/backend/application/ports/idea-evaluator";
import {
  createIdeaTitle,
  IdeaTitleError,
} from "@/backend/domain/game/idea-creation";

export type CreateIdeaInput = {
  runId: string;
  title: string;
  description?: string;
  expectedVersion: number;
};

export type CreateIdeaResult = {
  ideaId: string;
  evaluationStatus: "completed" | "fallback";
};

export type CreateIdeaErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "IDEA_WEEKLY_LIMIT"
  | "IDEA_STOCK_FULL"
  | "VALIDATION_ERROR"
  | "COMMIT_FAILED";

export class CreateIdeaError extends Error {
  constructor(readonly code: CreateIdeaErrorCode) {
    super("企画を作成できませんでした。");
    this.name = "CreateIdeaError";
  }
}

export type CreateIdeaDependencies = {
  ideas: CreateIdeaRepository;
  evaluator: IdeaEvaluator;
};

export async function createIdea(
  context: UseCaseContext,
  input: CreateIdeaInput,
  dependencies: CreateIdeaDependencies,
): Promise<CreateIdeaResult> {
  const run = await dependencies.ideas.findRun({
    actorUserId: context.actorUserId,
    runId: input.runId,
  });
  assertRunCanCreateIdea(run, input.expectedVersion);

  let title;
  try {
    title = createIdeaTitle(input.title);
  } catch (error) {
    if (error instanceof IdeaTitleError) {
      throw new CreateIdeaError("VALIDATION_ERROR");
    }
    throw error;
  }

  const capacity = await dependencies.ideas.getCapacity({
    actorUserId: context.actorUserId,
    runId: input.runId,
    weekNumber: run.currentWeek,
  });
  if (!capacity) {
    throw new CreateIdeaError("RUN_NOT_FOUND");
  }
  if (capacity.ideasCreatedThisWeek >= capacity.ideasPerWeekLimit) {
    throw new CreateIdeaError("IDEA_WEEKLY_LIMIT");
  }
  if (capacity.pendingIdeaCount >= capacity.ideaStockLimit) {
    throw new CreateIdeaError("IDEA_STOCK_FULL");
  }
  if (capacity.isActivityUnavailable) {
    throw new CreateIdeaError("ACTIVITY_UNAVAILABLE");
  }

  const evaluation = await dependencies.evaluator.evaluate({
    title,
    channelType: run.channelType,
    specialty: run.specialty,
  });

  try {
    const committedIdea = await dependencies.ideas.commitCreateIdea({
      actorUserId: context.actorUserId,
      runId: input.runId,
      expectedVersion: input.expectedVersion,
      title,
      description: input.description ?? null,
      evaluation,
    });

    return {
      ideaId: committedIdea.ideaId,
      evaluationStatus: evaluation.status,
    };
  } catch (error) {
    if (error instanceof CommitCreateIdeaError) {
      throw new CreateIdeaError(error.code);
    }
    throw error;
  }
}

function assertRunCanCreateIdea(
  lookup: CreateIdeaRunLookup,
  expectedVersion: number,
): asserts lookup is Extract<CreateIdeaRunLookup, { status: "found" }> {
  if (lookup.status === "not_found") {
    throw new CreateIdeaError("RUN_NOT_FOUND");
  }
  if (lookup.status === "forbidden") {
    throw new CreateIdeaError("FORBIDDEN");
  }
  if (lookup.runStatus !== "playing") {
    throw new CreateIdeaError("RUN_NOT_PLAYABLE");
  }
  if (lookup.stateVersion !== expectedVersion) {
    throw new CreateIdeaError("STALE_STATE");
  }
}
