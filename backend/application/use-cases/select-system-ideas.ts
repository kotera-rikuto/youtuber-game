import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { RandomSource } from "@/backend/application/ports/random-source";
import {
  CommitSystemIdeaCycleError,
  type SystemIdeaRepository,
} from "@/backend/application/ports/system-idea-repository";
import {
  createSystemIdeaCycle,
  resolveSystemIdeaPool,
  selectSystemIdeasWithoutRepeat,
  SystemIdeaCycleIntegrityError,
  type SelectedSystemIdea,
  type SystemIdeaCycle,
} from "@/backend/domain/game/system-idea-cycle";

export type SelectSystemIdeasInput = {
  runId: string;
  requiredCount: number;
};

export type SelectSystemIdeasDependencies = {
  systemIdeas: SystemIdeaRepository;
  randomSource: RandomSource;
};

export type SelectSystemIdeasErrorCode =
  | "RUN_NOT_FOUND"
  | "INVALID_COUNT"
  | "INVALID_POOL"
  | "INVALID_CYCLE"
  | "CYCLE_CONFLICT";

export class SelectSystemIdeasError extends Error {
  constructor(readonly code: SelectSystemIdeasErrorCode) {
    super("システム企画を選出できませんでした。");
    this.name = "SelectSystemIdeasError";
  }
}

export async function selectSystemIdeas(
  context: UseCaseContext,
  input: SelectSystemIdeasInput,
  dependencies: SelectSystemIdeasDependencies,
): Promise<readonly SelectedSystemIdea[]> {
  const query = { actorUserId: context.actorUserId, runId: input.runId };

  let cycles = await dependencies.systemIdeas.listCycles(query);
  if (cycles === null) {
    throw new SelectSystemIdeasError("RUN_NOT_FOUND");
  }

  let pool;
  if (input.requiredCount > 0) {
    const candidates = await dependencies.systemIdeas.findPool(query);
    if (candidates === null) {
      throw new SelectSystemIdeasError("RUN_NOT_FOUND");
    }
    try {
      pool = resolveSystemIdeaPool(candidates);
    } catch (error) {
      if (error instanceof SystemIdeaCycleIntegrityError) {
        throw new SelectSystemIdeasError("INVALID_POOL");
      }
      throw error;
    }
  } else {
    return trySelect(cycles, 0) ?? [];
  }

  const existingSelection = trySelect(cycles, input.requiredCount);
  if (existingSelection) {
    return existingSelection;
  }

  const previousLastTemplateId = getPreviousLastTemplateId(cycles);
  const draft = createSystemIdeaCycle(
    pool,
    previousLastTemplateId,
    dependencies.randomSource,
  );

  try {
    await dependencies.systemIdeas.commitCycle({
      ...query,
      requiredCount: input.requiredCount,
      orderedRuleSetSystemIdeaIds: draft.map(
        (entry) => entry.ruleSetSystemIdeaId,
      ),
    });
  } catch (error) {
    if (error instanceof CommitSystemIdeaCycleError) {
      throw new SelectSystemIdeasError(mapCommitError(error));
    }
    throw error;
  }

  cycles = await dependencies.systemIdeas.listCycles(query);
  if (cycles === null) {
    throw new SelectSystemIdeasError("RUN_NOT_FOUND");
  }

  const committedSelection = trySelect(cycles, input.requiredCount);
  if (!committedSelection) {
    throw new SelectSystemIdeasError("CYCLE_CONFLICT");
  }
  return committedSelection;
}

function trySelect(
  cycles: readonly SystemIdeaCycle[],
  requiredCount: number,
) {
  try {
    return selectSystemIdeasWithoutRepeat(cycles, requiredCount);
  } catch (error) {
    if (!(error instanceof SystemIdeaCycleIntegrityError)) {
      throw error;
    }
    if (error.code === "INSUFFICIENT_ENTRIES") {
      return null;
    }
    if (error.code === "INVALID_SELECTION_COUNT") {
      throw new SelectSystemIdeasError("INVALID_COUNT");
    }
    throw new SelectSystemIdeasError("INVALID_CYCLE");
  }
}

function getPreviousLastTemplateId(cycles: readonly SystemIdeaCycle[]) {
  const previousCycle = [...cycles].sort(
    (left, right) => right.cycleNumber - left.cycleNumber,
  )[0];
  return previousCycle
    ? [...previousCycle.entries].sort(
        (left, right) => right.position - left.position,
      )[0]?.templateId ?? null
    : null;
}

function mapCommitError(
  error: CommitSystemIdeaCycleError,
): SelectSystemIdeasErrorCode {
  switch (error.code) {
    case "RUN_NOT_FOUND":
      return "RUN_NOT_FOUND";
    case "POOL_INVALID":
      return "INVALID_POOL";
    case "CYCLE_CONFLICT":
    case "COMMIT_FAILED":
      return "CYCLE_CONFLICT";
  }
}
