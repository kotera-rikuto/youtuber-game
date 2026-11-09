import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type {
  GameRunRepository,
  StartGameCommand,
  StartGameCommitResult,
} from "@/backend/application/ports/game-run-repository";
import type {
  IdeasCreatedInWeekQuery,
  IdeaStockRepository,
} from "@/backend/application/ports/idea-stock-repository";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { RuleRepository } from "@/backend/application/ports/rule-repository";
import type {
  CommittedWeekQuery,
  IdempotentWeekResultQuery,
  WeekResultRepository,
} from "@/backend/application/ports/week-result-repository";
import type { FinalGameRun, GameRun } from "@/backend/domain/game/game-run";
import type { IdeaQueue } from "@/backend/domain/game/idea-stock";
import type {
  ChannelRule,
  PostingFrequencyRule,
  PublishedRuleSet,
  SpecialtyRule,
} from "@/backend/domain/game/rules";
import type { WeekResult } from "@/backend/domain/game/week-result";

export class InMemoryGameRunRepository implements GameRunRepository {
  readonly findActiveByOwnerCalls: UseCaseContext["actorUserId"][] = [];
  readonly findCurrentByIdCalls: OwnedRunQuery[] = [];
  readonly commitStartGameCalls: StartGameCommand[] = [];

  constructor(
    private readonly runs: readonly GameRun[] = [],
    private readonly startGameResult: StartGameCommitResult = {
      runId: "created-run-id",
    },
  ) {}

  async findActiveByOwner(actorUserId: UseCaseContext["actorUserId"]) {
    this.findActiveByOwnerCalls.push(actorUserId);
    const run = this.runs.find(
      (candidate) =>
        candidate.ownerUserId === actorUserId &&
        (candidate.status === "playing" || candidate.status === "stage_cleared"),
    );
    return clone(run ?? null);
  }

  async findCurrentById(query: OwnedRunQuery) {
    this.findCurrentByIdCalls.push(clone(query));
    const run = this.runs.find(
      (candidate) =>
        candidate.id === query.runId &&
        candidate.ownerUserId === query.actorUserId &&
        (candidate.status === "playing" || candidate.status === "stage_cleared"),
    );
    return clone(run ?? null);
  }

  async findFinalById(query: OwnedRunQuery): Promise<FinalGameRun | null> {
    const run = this.runs.find(
      (candidate) =>
        candidate.id === query.runId && candidate.ownerUserId === query.actorUserId,
    );
    if (!run) return null;
    return {
      id: run.id,
      ownerUserId: run.ownerUserId,
      channelName: run.channelName,
      channelType: run.channelType,
      specialty: run.specialty,
      status: run.status,
      completedAt: run.completedAt,
      currentState: {
        currentWeek: run.currentState.currentWeek,
        cash: run.currentState.cash,
        energy: run.currentState.energy,
        subscribers: run.currentState.subscribers,
        cumulativeViews: run.currentState.cumulativeViews,
        flameCount: run.currentState.flameCount,
      },
      termination: null,
      finalStage: run.currentGoal
        ? {
            stageNumber: run.currentGoal.stageNumber,
            targetSubscribers: run.currentGoal.targetSubscribers,
            startedWeek: run.currentGoal.startedWeek,
            deadlineWeek: run.currentGoal.deadlineWeek,
            achievedWeek: null,
            isFinal: run.currentGoal.isFinal,
          }
        : null,
    };
  }

  async commitStartGame(command: StartGameCommand) {
    this.commitStartGameCalls.push(clone(command));
    return clone(this.startGameResult);
  }
}

type IdeaStockFixture = {
  ownerUserId: string;
  queue: IdeaQueue;
  createdCountByWeek?: Readonly<Record<number, number>>;
};

export class InMemoryIdeaStockRepository implements IdeaStockRepository {
  readonly pendingQueueCalls: OwnedRunQuery[] = [];
  readonly countPendingCalls: OwnedRunQuery[] = [];
  readonly countCreatedInWeekCalls: IdeasCreatedInWeekQuery[] = [];

  constructor(private readonly stocks: readonly IdeaStockFixture[] = []) {}

  async getPendingQueue(query: OwnedRunQuery) {
    this.pendingQueueCalls.push(clone(query));
    return clone(this.findOwnedStock(query)?.queue ?? null);
  }

  async countPending(query: OwnedRunQuery) {
    this.countPendingCalls.push(clone(query));
    return this.findOwnedStock(query)?.queue.items.length ?? null;
  }

  async countCreatedInWeek(query: IdeasCreatedInWeekQuery) {
    this.countCreatedInWeekCalls.push(clone(query));
    const stock = this.findOwnedStock(query);
    return stock ? (stock.createdCountByWeek?.[query.weekNumber] ?? 0) : null;
  }

  private findOwnedStock(query: OwnedRunQuery) {
    return this.stocks.find(
      (stock) =>
        stock.queue.runId === query.runId &&
        stock.ownerUserId === query.actorUserId,
    );
  }
}

type RuleFixtures = {
  ruleSets?: readonly PublishedRuleSet[];
  channelRules?: readonly ChannelRule[];
  specialties?: readonly SpecialtyRule[];
  postingFrequencies?: readonly PostingFrequencyRule[];
};

export class InMemoryRuleRepository implements RuleRepository {
  constructor(private readonly fixtures: RuleFixtures = {}) {}

  async findActiveRuleSet() {
    return clone(
      this.fixtures.ruleSets?.find((ruleSet) => ruleSet.status === "active") ??
        null,
    );
  }

  async findPublishedRuleSetById(ruleSetId: string) {
    return clone(
      this.fixtures.ruleSets?.find((ruleSet) => ruleSet.id === ruleSetId) ??
        null,
    );
  }

  async listChannelRules(ruleSetId: string) {
    return clone(
      this.fixtures.channelRules?.filter(
        (rule) => rule.ruleSetId === ruleSetId,
      ) ?? [],
    );
  }

  async listSpecialties(ruleSetId: string) {
    return clone(
      this.fixtures.specialties?.filter(
        (rule) => rule.ruleSetId === ruleSetId,
      ) ?? [],
    );
  }

  async listPostingFrequencies(ruleSetId: string) {
    return clone(
      this.fixtures.postingFrequencies?.filter(
        (rule) => rule.ruleSetId === ruleSetId,
      ) ?? [],
    );
  }
}

export type OwnedRunFixture = {
  ownerUserId: string;
  runId: string;
};

export type WeekResultFixture = {
  result: WeekResult;
  idempotencyKey: string;
};

export type WeekResultRepositoryFixtures = {
  ownedRuns?: readonly OwnedRunFixture[];
  results?: readonly WeekResultFixture[];
};

export class InMemoryWeekResultRepository implements WeekResultRepository {
  readonly committedWeekCalls: CommittedWeekQuery[] = [];
  readonly idempotencyCalls: IdempotentWeekResultQuery[] = [];
  readonly historyCalls: OwnedRunQuery[] = [];
  private readonly fixtures: {
    ownedRuns: readonly OwnedRunFixture[];
    results: readonly WeekResultFixture[];
  };

  constructor(fixtures: WeekResultRepositoryFixtures = {}) {
    this.fixtures = clone({
      ownedRuns: fixtures.ownedRuns ?? [],
      results: fixtures.results ?? [],
    });
  }

  async findCommittedWeek(query: CommittedWeekQuery) {
    this.committedWeekCalls.push(clone(query));
    return clone(
      this.findOwnedResults(query).find(
        (fixture) => fixture.result.weekNumber === query.weekNumber,
      )?.result ?? null,
    );
  }

  async findByIdempotencyKey(query: IdempotentWeekResultQuery) {
    this.idempotencyCalls.push(clone(query));
    return clone(
      this.findOwnedResults(query).find(
        (fixture) => fixture.idempotencyKey === query.idempotencyKey,
      )?.result ?? null,
    );
  }

  async listHistory(query: OwnedRunQuery) {
    this.historyCalls.push(clone(query));
    if (!this.ownsRun(query)) {
      return null;
    }

    return clone(
      this.findOwnedResults(query)
        .map((fixture) => fixture.result)
        .sort((left, right) => left.weekNumber - right.weekNumber),
    );
  }

  private ownsRun(query: OwnedRunQuery) {
    return this.fixtures.ownedRuns.some(
      (run) =>
        run.runId === query.runId && run.ownerUserId === query.actorUserId,
    );
  }

  private findOwnedResults(query: OwnedRunQuery) {
    if (!this.ownsRun(query)) {
      return [];
    }

    return this.fixtures.results.filter(
      (fixture) => fixture.result.runId === query.runId,
    );
  }
}

function clone<T>(value: T): T {
  return structuredClone(value);
}
