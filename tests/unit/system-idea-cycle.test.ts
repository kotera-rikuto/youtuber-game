import {
  createSystemIdeaCycle,
  resolveSystemIdeaPool,
  selectSystemIdeasWithoutRepeat,
  SystemIdeaCycleIntegrityError,
  type SystemIdeaCycle,
  type SystemIdeaPoolCandidate,
} from "@/backend/domain/game/system-idea-cycle";
import { SequenceRandomSource } from "@/tests/support/sequence-random-source";
import { describe, expect, it } from "vitest";

describe("resolveSystemIdeaPool", () => {
  it("accepts exactly 50 unique templates", () => {
    expect(resolveSystemIdeaPool(createPool())).toHaveLength(50);
  });

  it.each([49, 51])("rejects a %s-entry pool", (size) => {
    expect(() => resolveSystemIdeaPool(createPool(size))).toThrowError(
      expect.objectContaining({ code: "INVALID_POOL_SIZE" }),
    );
  });

  it("rejects duplicate templates", () => {
    const pool = createPool();
    pool[49] = { ...pool[49]!, templateId: pool[0]!.templateId };

    expect(() => resolveSystemIdeaPool(pool)).toThrowError(
      expect.objectContaining({ code: "DUPLICATE_TEMPLATE" }),
    );
  });
});

describe("createSystemIdeaCycle", () => {
  it("reproduces an unbiased Fisher-Yates order with a fixed RandomSource", () => {
    const first = createSystemIdeaCycle(
      createPool(),
      null,
      new SequenceRandomSource(Array(49).fill(0)),
    );
    const second = createSystemIdeaCycle(
      createPool(),
      null,
      new SequenceRandomSource(Array(49).fill(0)),
    );

    expect(first).toEqual(second);
    expect(first.map((entry) => entry.position)).toEqual(
      Array.from({ length: 50 }, (_, index) => index + 1),
    );
    expect(new Set(first.map((entry) => entry.templateId)).size).toBe(50);
  });

  it("deterministically swaps the first two entries at a cycle boundary", () => {
    const randomValues = Array(49).fill(0);
    const unadjusted = createSystemIdeaCycle(
      createPool(),
      null,
      new SequenceRandomSource(randomValues),
    );
    const adjusted = createSystemIdeaCycle(
      createPool(),
      unadjusted[0]!.templateId,
      new SequenceRandomSource(randomValues),
    );

    expect(adjusted[0]!.templateId).toBe(unadjusted[1]!.templateId);
    expect(adjusted[1]!.templateId).toBe(unadjusted[0]!.templateId);
    expect(adjusted[0]!.templateId).not.toBe(
      unadjusted[0]!.templateId,
    );
  });
});

describe("selectSystemIdeasWithoutRepeat", () => {
  it("selects the earliest unused positions and skips used entries", () => {
    const cycle = createPersistedCycle(1, 3);

    expect(selectSystemIdeasWithoutRepeat([cycle], 3)).toEqual([
      { postOrder: 1, cycleEntryId: "entry-1-4", title: "Title 4" },
      { postOrder: 2, cycleEntryId: "entry-1-5", title: "Title 5" },
      { postOrder: 3, cycleEntryId: "entry-1-6", title: "Title 6" },
    ]);
  });

  it("uses the old cycle remainder before the next cycle", () => {
    const firstCycle = createPersistedCycle(1, 48);
    const secondCycle = createPersistedCycle(2, 0);

    expect(
      selectSystemIdeasWithoutRepeat([secondCycle, firstCycle], 5).map(
        (idea) => idea.cycleEntryId,
      ),
    ).toEqual([
      "entry-1-49",
      "entry-1-50",
      "entry-2-1",
      "entry-2-2",
      "entry-2-3",
    ]);
  });

  it("does not reuse a template before 50 entries are consumed", () => {
    const firstCycle = createPersistedCycle(1, 49);
    const secondCycle = createPersistedCycle(2, 0);

    expect(
      selectSystemIdeasWithoutRepeat([firstCycle, secondCycle], 1)[0]
        ?.cycleEntryId,
    ).toBe("entry-1-50");
  });

  it("allows templates to be reused in the next cycle after all 50 are consumed", () => {
    const firstCycle = createPersistedCycle(1, 50);
    const secondCycle = createPersistedCycle(2, 0);

    expect(
      selectSystemIdeasWithoutRepeat([firstCycle, secondCycle], 1)[0],
    ).toMatchObject({
      cycleEntryId: "entry-2-1",
      title: "Title 1",
    });
  });

  it.each([-1, 8, 1.5])("rejects invalid request count %s", (count) => {
    expect(() =>
      selectSystemIdeasWithoutRepeat([createPersistedCycle(1, 0)], count),
    ).toThrowError(
      expect.objectContaining({ code: "INVALID_SELECTION_COUNT" }),
    );
  });

  it("rejects malformed persisted cycles", () => {
    const cycle = createPersistedCycle(1, 0);

    expect(() =>
      selectSystemIdeasWithoutRepeat(
        [{ ...cycle, entries: cycle.entries.slice(0, 49) }],
        1,
      ),
    ).toThrow(SystemIdeaCycleIntegrityError);
  });
});

function createPool(size = 50): SystemIdeaPoolCandidate[] {
  return Array.from({ length: size }, (_, index) => ({
    ruleSetSystemIdeaId: `association-${index + 1}`,
    templateId: `template-${index + 1}`,
    title: `Title ${index + 1}`,
  }));
}

function createPersistedCycle(
  cycleNumber: number,
  usedCount: number,
): SystemIdeaCycle {
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
