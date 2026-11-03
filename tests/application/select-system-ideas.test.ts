import { requireUseCaseContext } from "@/backend/application/auth/authentication";
import type {
  CommitSystemIdeaCycleCommand,
  SystemIdeaRepository,
} from "@/backend/application/ports/system-idea-repository";
import {
  selectSystemIdeas,
  type SelectSystemIdeasDependencies,
} from "@/backend/application/use-cases/select-system-ideas";
import type {
  SystemIdeaCycle,
  SystemIdeaPoolCandidate,
} from "@/backend/domain/game/system-idea-cycle";
import { SequenceRandomSource } from "@/tests/support/sequence-random-source";
import { describe, expect, it } from "vitest";

describe("selectSystemIdeas", () => {
  it("creates an initial cycle and returns titles with cycle entry ids in post order", async () => {
    const dependencies = createDependencies();

    const selected = await selectSystemIdeas(
      await contextFor("owner"),
      { runId: "run", requiredCount: 3 },
      dependencies,
    );

    expect(selected).toHaveLength(3);
    expect(selected.map((idea) => idea.postOrder)).toEqual([1, 2, 3]);
    expect(selected.every((idea) => idea.cycleEntryId.length > 0)).toBe(true);
    expect(dependencies.systemIdeas.commitCalls).toHaveLength(1);
    expect(
      new Set(
        dependencies.systemIdeas.commitCalls[0]
          ?.orderedRuleSetSystemIdeaIds,
      ).size,
    ).toBe(50);
  });

  it("uses the current cycle without creating another when enough entries remain", async () => {
    const dependencies = createDependencies({
      cycles: [createCycle(1, 45)],
      randomValues: [],
    });

    const selected = await selectSystemIdeas(
      await contextFor("owner"),
      { runId: "run", requiredCount: 5 },
      dependencies,
    );

    expect(selected.map((idea) => idea.cycleEntryId)).toEqual([
      "entry-1-46",
      "entry-1-47",
      "entry-1-48",
      "entry-1-49",
      "entry-1-50",
    ]);
    expect(dependencies.systemIdeas.commitCalls).toHaveLength(0);
  });

  it("uses a two-entry remainder before three entries from a new cycle", async () => {
    const dependencies = createDependencies({ cycles: [createCycle(1, 48)] });

    const selected = await selectSystemIdeas(
      await contextFor("owner"),
      { runId: "run", requiredCount: 5 },
      dependencies,
    );

    expect(selected.slice(0, 2).map((idea) => idea.cycleEntryId)).toEqual([
      "entry-1-49",
      "entry-1-50",
    ]);
    expect(selected.slice(2).every((idea) => idea.cycleEntryId.startsWith("entry-2-"))).toBe(
      true,
    );
  });

  it("avoids the previous cycle's last template at the next boundary", async () => {
    const previous = createCycle(1, 50);
    const dependencies = createDependencies({ cycles: [previous] });
    const previousLastTemplateId = previous.entries[49]!.templateId;

    await selectSystemIdeas(
      await contextFor("owner"),
      { runId: "run", requiredCount: 1 },
      dependencies,
    );

    const firstAssociationId =
      dependencies.systemIdeas.commitCalls[0]
        ?.orderedRuleSetSystemIdeaIds[0];
    const firstTemplateId = dependencies.systemIdeas.pool.find(
      (idea) => idea.ruleSetSystemIdeaId === firstAssociationId,
    )?.templateId;
    expect(firstTemplateId).not.toBe(previousLastTemplateId);
  });

  it.each([49, 51])("rejects an invalid %s-entry database pool", async (size) => {
    const dependencies = createDependencies({ pool: createPool(size) });

    await expect(
      selectSystemIdeas(
        await contextFor("owner"),
        { runId: "run", requiredCount: 1 },
        dependencies,
      ),
    ).rejects.toMatchObject({ code: "INVALID_POOL" });
    expect(dependencies.systemIdeas.commitCalls).toHaveLength(0);
  });

  it("rejects a duplicate template in the database pool", async () => {
    const pool = createPool();
    pool[49] = { ...pool[49]!, templateId: pool[0]!.templateId };
    const dependencies = createDependencies({ pool });

    await expect(
      selectSystemIdeas(
        await contextFor("owner"),
        { runId: "run", requiredCount: 1 },
        dependencies,
      ),
    ).rejects.toMatchObject({ code: "INVALID_POOL" });
  });

  it("does not expose another owner's run", async () => {
    const dependencies = createDependencies({ ownerUserId: "owner" });

    await expect(
      selectSystemIdeas(
        await contextFor("other"),
        { runId: "run", requiredCount: 1 },
        dependencies,
      ),
    ).rejects.toMatchObject({ code: "RUN_NOT_FOUND" });
  });

  it("accepts zero without touching the pool or random source", async () => {
    const dependencies = createDependencies({ pool: [], randomValues: [] });

    await expect(
      selectSystemIdeas(
        await contextFor("owner"),
        { runId: "run", requiredCount: 0 },
        dependencies,
      ),
    ).resolves.toEqual([]);
  });
});

class FakeSystemIdeaRepository implements SystemIdeaRepository {
  readonly commitCalls: CommitSystemIdeaCycleCommand[] = [];

  constructor(
    readonly pool: readonly SystemIdeaPoolCandidate[],
    private readonly ownerUserId: string,
    private cycles: SystemIdeaCycle[],
  ) {}

  async findPool(query: { actorUserId: string }) {
    return query.actorUserId === this.ownerUserId ? this.pool : null;
  }

  async listCycles(query: { actorUserId: string }) {
    return query.actorUserId === this.ownerUserId ? this.cycles : null;
  }

  async commitCycle(command: CommitSystemIdeaCycleCommand) {
    this.commitCalls.push(command);
    const cycleNumber = this.cycles.length + 1;
    const ideasByAssociationId = new Map(
      this.pool.map((idea) => [idea.ruleSetSystemIdeaId, idea]),
    );
    this.cycles = [
      ...this.cycles,
      {
        id: `cycle-${cycleNumber}`,
        cycleNumber,
        entries: command.orderedRuleSetSystemIdeaIds.map(
          (associationId, index) => {
            const idea = ideasByAssociationId.get(associationId);
            if (!idea) {
              throw new Error("Unknown fake system idea association.");
            }
            return {
              ...idea,
              id: `entry-${cycleNumber}-${index + 1}`,
              position: index + 1,
              isUsed: false,
            };
          },
        ),
      },
    ];
    return { cycleId: `cycle-${cycleNumber}` };
  }
}

function createDependencies(options: {
  pool?: readonly SystemIdeaPoolCandidate[];
  cycles?: readonly SystemIdeaCycle[];
  ownerUserId?: string;
  randomValues?: readonly number[];
} = {}): SelectSystemIdeasDependencies & {
  systemIdeas: FakeSystemIdeaRepository;
} {
  return {
    systemIdeas: new FakeSystemIdeaRepository(
      options.pool ?? createPool(),
      options.ownerUserId ?? "owner",
      [...(options.cycles ?? [])],
    ),
    randomSource: new SequenceRandomSource(
      options.randomValues ?? Array(49).fill(0),
    ),
  };
}

function createPool(size = 50): SystemIdeaPoolCandidate[] {
  return Array.from({ length: size }, (_, index) => ({
    ruleSetSystemIdeaId: `association-${index + 1}`,
    templateId: `template-${index + 1}`,
    title: `Title ${index + 1}`,
  }));
}

function createCycle(cycleNumber: number, usedCount: number): SystemIdeaCycle {
  return {
    id: `cycle-${cycleNumber}`,
    cycleNumber,
    entries: createPool().map((idea, index) => ({
      ...idea,
      id: `entry-${cycleNumber}-${index + 1}`,
      position: index + 1,
      isUsed: index < usedCount,
    })),
  };
}

async function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
