import { describe, expect, it } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import {
  CommitCreateIdeaError,
  type CommitCreateIdeaCommand,
  type CreateIdeaCapacity,
  type CreateIdeaRepository,
  type CreateIdeaRunLookup,
} from "@/backend/application/ports/create-idea-repository";
import type {
  IdeaEvaluationResult,
  IdeaEvaluator,
} from "@/backend/application/ports/idea-evaluator";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import {
  createIdea,
  type CreateIdeaInput,
} from "@/backend/application/use-cases/create-idea";

const completedEvaluation: IdeaEvaluationResult = {
  score: 84,
  status: "completed",
  model: "evaluation-model-2026-11-03",
  promptVersion: "idea-evaluation-v1",
};

const fallbackEvaluation: IdeaEvaluationResult = {
  score: 60,
  status: "fallback",
  model: "evaluation-model",
  promptVersion: "idea-evaluation-v1",
};

describe("createIdea", () => {
  it("normalizes the title, evaluates once outside the command, and returns no score", async () => {
    const events: string[] = [];
    const repository = new FakeCreateIdeaRepository({ events });
    const evaluator = new FakeIdeaEvaluator(completedEvaluation, events);
    const context = await contextFor("verified-owner");

    const result = await createIdea(
      context,
      {
        runId: "run-1",
        title: "  新しい企画  ",
        description: "説明は上限を追加せず保存する",
        expectedVersion: 7,
      },
      { ideas: repository, evaluator },
    );

    expect(result).toEqual({
      ideaId: "created-idea-id",
      evaluationStatus: "completed",
    });
    expect(result).not.toHaveProperty("score");
    expect(result).not.toHaveProperty("model");
    expect(evaluator.calls).toEqual([
      {
        title: "新しい企画",
        channelType: "mainstream",
        specialty: null,
      },
    ]);
    expect(repository.commands).toEqual([
      {
        actorUserId: context.actorUserId,
        runId: "run-1",
        expectedVersion: 7,
        title: "新しい企画",
        description: "説明は上限を追加せず保存する",
        evaluation: completedEvaluation,
      },
    ]);
    expect(events).toEqual(["findRun", "getCapacity", "evaluate", "commit"]);
  });

  it.each(["企", "企".repeat(100)])(
    "accepts a title containing %i characters",
    async (title) => {
      const dependencies = createDependencies();

      await expect(
        createIdea(await contextFor("owner"), validInput({ title }), dependencies),
      ).resolves.toMatchObject({ ideaId: "created-idea-id" });
      expect(dependencies.evaluator.calls).toHaveLength(1);
    },
  );

  it.each(["", " \n\t ", "企".repeat(101)])(
    "rejects an empty or overlong title before evaluation",
    async (title) => {
      const dependencies = createDependencies();

      await expect(
        createIdea(await contextFor("owner"), validInput({ title }), dependencies),
      ).rejects.toMatchObject({ code: "VALIDATION_ERROR" });
      expect(dependencies.evaluator.calls).toHaveLength(0);
      expect(dependencies.ideas.commands).toHaveLength(0);
    },
  );

  it.each([
    [{ status: "not_found" } as const, "RUN_NOT_FOUND"],
    [{ status: "forbidden" } as const, "FORBIDDEN"],
    [readyRun({ runStatus: "stage_cleared" }), "RUN_NOT_PLAYABLE"],
    [readyRun({ runStatus: "game_over" }), "RUN_NOT_PLAYABLE"],
    [readyRun({ stateVersion: 8 }), "STALE_STATE"],
  ])("rejects an unusable run before evaluation", async (lookup, code) => {
    const dependencies = createDependencies({ lookup });

    await expect(
      createIdea(await contextFor("owner"), validInput(), dependencies),
    ).rejects.toMatchObject({ code });
    expect(dependencies.evaluator.calls).toHaveLength(0);
    expect(dependencies.ideas.capacityQueries).toHaveLength(0);
  });

  it("uses only the verified context as owner", async () => {
    const dependencies = createDependencies();
    const context = await contextFor("verified-owner");
    const input = {
      ...validInput(),
      userId: "forged-owner",
    } as CreateIdeaInput;

    await createIdea(context, input, dependencies);

    expect(dependencies.ideas.findRunQueries[0]?.actorUserId).toBe(
      context.actorUserId,
    );
    expect(dependencies.ideas.commands[0]?.actorUserId).toBe(
      context.actorUserId,
    );
    expect(dependencies.ideas.commands[0]).not.toHaveProperty("userId");
  });

  it.each([
    [capacity({ ideasCreatedThisWeek: 3 }), "IDEA_WEEKLY_LIMIT"],
    [capacity({ pendingIdeaCount: 30 }), "IDEA_STOCK_FULL"],
    [capacity({ isActivityUnavailable: true }), "ACTIVITY_UNAVAILABLE"],
  ])("rejects exhausted capacity before evaluation", async (limit, code) => {
    const dependencies = createDependencies({ capacity: limit });

    await expect(
      createIdea(await contextFor("owner"), validInput(), dependencies),
    ).rejects.toMatchObject({ code });
    expect(dependencies.evaluator.calls).toHaveLength(0);
    expect(dependencies.ideas.commands).toHaveLength(0);
  });

  it.each([
    capacity({ ideasCreatedThisWeek: 2 }),
    capacity({ pendingIdeaCount: 29 }),
  ])("allows creation at the final capacity slot", async (availableCapacity) => {
    const dependencies = createDependencies({ capacity: availableCapacity });

    await expect(
      createIdea(await contextFor("owner"), validInput(), dependencies),
    ).resolves.toMatchObject({ ideaId: "created-idea-id" });
    expect(dependencies.evaluator.calls).toHaveLength(1);
  });

  it("uses limits supplied by the run's rules instead of hard-coded limits", async () => {
    const dependencies = createDependencies({
      capacity: capacity({
        ideasCreatedThisWeek: 2,
        ideasPerWeekLimit: 2,
        pendingIdeaCount: 5,
        ideaStockLimit: 5,
      }),
    });

    await expect(
      createIdea(await contextFor("owner"), validInput(), dependencies),
    ).rejects.toMatchObject({ code: "IDEA_WEEKLY_LIMIT" });
    expect(dependencies.evaluator.calls).toHaveLength(0);
  });

  it("commits fallback score 60 and its audit metadata", async () => {
    const dependencies = createDependencies({ evaluation: fallbackEvaluation });

    await expect(
      createIdea(await contextFor("owner"), validInput(), dependencies),
    ).resolves.toEqual({
      ideaId: "created-idea-id",
      evaluationStatus: "fallback",
    });
    expect(dependencies.ideas.commands[0]?.evaluation).toEqual(
      fallbackEvaluation,
    );
  });

  it.each([
    "STALE_STATE",
    "ACTIVITY_UNAVAILABLE",
    "IDEA_WEEKLY_LIMIT",
    "IDEA_STOCK_FULL",
  ] as const)("maps a post-evaluation database rejection: %s", async (code) => {
    const dependencies = createDependencies({ commitError: code });

    await expect(
      createIdea(await contextFor("owner"), validInput(), dependencies),
    ).rejects.toMatchObject({ code });
    expect(dependencies.evaluator.calls).toHaveLength(1);
    expect(dependencies.ideas.commands).toHaveLength(1);
  });
});

class FakeCreateIdeaRepository implements CreateIdeaRepository {
  readonly findRunQueries: OwnedRunQuery[] = [];
  readonly capacityQueries: Array<OwnedRunQuery & { weekNumber: number }> = [];
  readonly commands: CommitCreateIdeaCommand[] = [];
  private readonly lookup: CreateIdeaRunLookup;
  private readonly availableCapacity: CreateIdeaCapacity | null;
  private readonly commitError?: CommitCreateIdeaError["code"];
  private readonly events: string[];

  constructor(options: {
    lookup?: CreateIdeaRunLookup;
    capacity?: CreateIdeaCapacity | null;
    commitError?: CommitCreateIdeaError["code"];
    events?: string[];
  } = {}) {
    this.lookup = options.lookup ?? readyRun();
    this.availableCapacity =
      options.capacity === undefined ? capacity() : options.capacity;
    this.commitError = options.commitError;
    this.events = options.events ?? [];
  }

  async findRun(query: OwnedRunQuery) {
    this.events.push("findRun");
    this.findRunQueries.push(structuredClone(query));
    return structuredClone(this.lookup);
  }

  async getCapacity(query: OwnedRunQuery & { weekNumber: number }) {
    this.events.push("getCapacity");
    this.capacityQueries.push(structuredClone(query));
    return structuredClone(this.availableCapacity);
  }

  async commitCreateIdea(command: CommitCreateIdeaCommand) {
    this.events.push("commit");
    this.commands.push(structuredClone(command));
    if (this.commitError) {
      throw new CommitCreateIdeaError(this.commitError);
    }
    return { ideaId: "created-idea-id" };
  }
}

class FakeIdeaEvaluator implements IdeaEvaluator {
  readonly calls: Array<{
    title: string;
    channelType: string;
    specialty: string | null;
  }> = [];

  constructor(
    private readonly evaluation: IdeaEvaluationResult,
    private readonly events: string[] = [],
  ) {}

  async evaluate(input: {
    title: string;
    channelType: string;
    specialty: string | null;
  }) {
    this.events.push("evaluate");
    this.calls.push(structuredClone(input));
    return structuredClone(this.evaluation);
  }
}

function createDependencies(options: {
  lookup?: CreateIdeaRunLookup;
  capacity?: CreateIdeaCapacity | null;
  evaluation?: IdeaEvaluationResult;
  commitError?: CommitCreateIdeaError["code"];
} = {}) {
  return {
    ideas: new FakeCreateIdeaRepository(options),
    evaluator: new FakeIdeaEvaluator(
      options.evaluation ?? completedEvaluation,
    ),
  };
}

function readyRun(
  overrides: Partial<Extract<CreateIdeaRunLookup, { status: "found" }>> = {},
): Extract<CreateIdeaRunLookup, { status: "found" }> {
  return {
    status: "found",
    runStatus: "playing",
    currentWeek: 4,
    stateVersion: 7,
    channelType: "mainstream",
    specialty: null,
    ...overrides,
  };
}

function capacity(
  overrides: Partial<CreateIdeaCapacity> = {},
): CreateIdeaCapacity {
  return {
    ideasCreatedThisWeek: 0,
    pendingIdeaCount: 0,
    ideasPerWeekLimit: 3,
    ideaStockLimit: 30,
    isActivityUnavailable: false,
    ...overrides,
  };
}

function validInput(overrides: Partial<CreateIdeaInput> = {}): CreateIdeaInput {
  return {
    runId: "run-1",
    title: "有効な企画",
    expectedVersion: 7,
    ...overrides,
  };
}

function contextFor(userId: string): Promise<UseCaseContext> {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
