export const SYSTEM_IDEA_POOL_SIZE = 50;
export const MAX_SYSTEM_IDEAS_PER_WEEK = 7;

export type SystemIdeaPoolCandidate = {
  ruleSetSystemIdeaId: string;
  templateId: string;
  title: string;
};

export type SystemIdeaCycleDraftEntry = SystemIdeaPoolCandidate & {
  position: number;
};

export type SystemIdeaCycleEntry = SystemIdeaCycleDraftEntry & {
  id: string;
  isUsed: boolean;
};

export type SystemIdeaCycle = {
  id: string;
  cycleNumber: number;
  entries: readonly SystemIdeaCycleEntry[];
};

export type SelectedSystemIdea = {
  postOrder: number;
  cycleEntryId: string;
  title: string;
};

export type IntegerRandomSource = {
  nextInt(minInclusive: number, maxInclusive: number): number;
};

export class SystemIdeaCycleIntegrityError extends Error {
  constructor(
    readonly code:
      | "INVALID_POOL_SIZE"
      | "DUPLICATE_TEMPLATE"
      | "INVALID_CYCLE"
      | "INVALID_SELECTION_COUNT"
      | "INSUFFICIENT_ENTRIES",
  ) {
    super("System idea cycle data is invalid.");
    this.name = "SystemIdeaCycleIntegrityError";
  }
}

export function resolveSystemIdeaPool(
  candidates: readonly SystemIdeaPoolCandidate[],
): readonly SystemIdeaPoolCandidate[] {
  if (candidates.length !== SYSTEM_IDEA_POOL_SIZE) {
    throw new SystemIdeaCycleIntegrityError("INVALID_POOL_SIZE");
  }

  const templateIds = new Set(candidates.map((candidate) => candidate.templateId));
  const associationIds = new Set(
    candidates.map((candidate) => candidate.ruleSetSystemIdeaId),
  );
  if (
    templateIds.size !== SYSTEM_IDEA_POOL_SIZE ||
    associationIds.size !== SYSTEM_IDEA_POOL_SIZE
  ) {
    throw new SystemIdeaCycleIntegrityError("DUPLICATE_TEMPLATE");
  }

  return [...candidates];
}

export function createSystemIdeaCycle(
  pool: readonly SystemIdeaPoolCandidate[],
  previousLastTemplateId: string | null,
  randomSource: IntegerRandomSource,
): readonly SystemIdeaCycleDraftEntry[] {
  const shuffled = [...resolveSystemIdeaPool(pool)];

  for (let currentIndex = shuffled.length - 1; currentIndex > 0; currentIndex -= 1) {
    const swapIndex = randomSource.nextInt(0, currentIndex);
    [shuffled[currentIndex], shuffled[swapIndex]] = [
      shuffled[swapIndex]!,
      shuffled[currentIndex]!,
    ];
  }

  if (shuffled[0]?.templateId === previousLastTemplateId) {
    [shuffled[0], shuffled[1]] = [shuffled[1]!, shuffled[0]!];
  }

  return shuffled.map((candidate, index) => ({
    ...candidate,
    position: index + 1,
  }));
}

export function selectSystemIdeasWithoutRepeat(
  cycles: readonly SystemIdeaCycle[],
  requestedCount: number,
): readonly SelectedSystemIdea[] {
  if (
    !Number.isSafeInteger(requestedCount) ||
    requestedCount < 0 ||
    requestedCount > MAX_SYSTEM_IDEAS_PER_WEEK
  ) {
    throw new SystemIdeaCycleIntegrityError("INVALID_SELECTION_COUNT");
  }

  const orderedCycles = [...cycles].sort(
    (left, right) => left.cycleNumber - right.cycleNumber,
  );
  validateCycles(orderedCycles);

  const availableEntries = orderedCycles.flatMap((cycle) =>
    [...cycle.entries]
      .sort((left, right) => left.position - right.position)
      .filter((entry) => !entry.isUsed),
  );
  if (availableEntries.length < requestedCount) {
    throw new SystemIdeaCycleIntegrityError("INSUFFICIENT_ENTRIES");
  }

  return availableEntries.slice(0, requestedCount).map((entry, index) => ({
    postOrder: index + 1,
    cycleEntryId: entry.id,
    title: entry.title,
  }));
}

function validateCycles(cycles: readonly SystemIdeaCycle[]) {
  const cycleNumbers = new Set<number>();
  const firstCycleNumber = cycles[0]?.cycleNumber ?? 1;
  for (const [cycleIndex, cycle] of cycles.entries()) {
    if (
      cycle.cycleNumber !== firstCycleNumber + cycleIndex ||
      cycleNumbers.has(cycle.cycleNumber) ||
      cycle.entries.length !== SYSTEM_IDEA_POOL_SIZE
    ) {
      throw new SystemIdeaCycleIntegrityError("INVALID_CYCLE");
    }
    cycleNumbers.add(cycle.cycleNumber);

    const positions = new Set(cycle.entries.map((entry) => entry.position));
    const templateIds = new Set(cycle.entries.map((entry) => entry.templateId));
    const entryIds = new Set(cycle.entries.map((entry) => entry.id));
    if (
      positions.size !== SYSTEM_IDEA_POOL_SIZE ||
      templateIds.size !== SYSTEM_IDEA_POOL_SIZE ||
      entryIds.size !== SYSTEM_IDEA_POOL_SIZE ||
      !Array.from(
        { length: SYSTEM_IDEA_POOL_SIZE },
        (_, index) => index + 1,
      ).every((position) => positions.has(position))
    ) {
      throw new SystemIdeaCycleIntegrityError("INVALID_CYCLE");
    }
  }
}
