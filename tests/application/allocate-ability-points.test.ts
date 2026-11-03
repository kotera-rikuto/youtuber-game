import { describe, expect, it } from "vitest";

import { requireUseCaseContext } from "@/backend/application/auth/authentication";
import {
  AllocateAbilityPointsCommitError,
  type AbilityAllocationRepository,
  type AllocateAbilityPointsCommand,
} from "@/backend/application/ports/ability-allocation-repository";
import {
  allocateAbilityPoints,
  type AllocateAbilityPointsInput,
} from "@/backend/application/use-cases/allocate-ability-points";

describe("allocateAbilityPoints", () => {
  it("commits all six abilities with the verified actor and returns the next version", async () => {
    const repository = new FakeAbilityAllocationRepository();
    const context = await contextFor("verified-owner");

    await expect(
      allocateAbilityPoints(context, validInput(), {
        abilityAllocations: repository,
      }),
    ).resolves.toEqual({ nextStateVersion: 8 });
    expect(repository.commands).toEqual([
      {
        actorUserId: context.actorUserId,
        runId: "run-1",
        allocations: {
          planning: 1,
          talking: 2,
          expertise: 3,
          editing: 4,
          visual: 5,
          filming: 6,
        },
        expectedVersion: 7,
      },
    ]);
  });

  it("allows a partial allocation with zeroes for unchanged abilities", async () => {
    const repository = new FakeAbilityAllocationRepository();

    await allocateAbilityPoints(
      await contextFor("owner"),
      validInput({ talking: 0, expertise: 0, editing: 0, visual: 0, filming: 0 }),
      { abilityAllocations: repository },
    );

    expect(repository.commands[0]?.allocations).toEqual({
      planning: 1,
      talking: 0,
      expertise: 0,
      editing: 0,
      visual: 0,
      filming: 0,
    });
  });

  it("allows an all-zero allocation because the specification requires nonnegative values without a positive-total constraint", async () => {
    const repository = new FakeAbilityAllocationRepository();

    await expect(
      allocateAbilityPoints(
        await contextFor("owner"),
        validInput({
          planning: 0,
          talking: 0,
          expertise: 0,
          editing: 0,
          visual: 0,
          filming: 0,
        }),
        { abilityAllocations: repository },
      ),
    ).resolves.toEqual({ nextStateVersion: 8 });
    expect(repository.commands).toHaveLength(1);
  });

  it.each([
    ["a negative value", { planning: -1 }],
    ["a fractional value", { talking: 0.5 }],
    ["NaN", { expertise: Number.NaN }],
    ["infinity", { editing: Number.POSITIVE_INFINITY }],
    ["a string value", { visual: "1" }],
    ["a missing ability", { filming: undefined }],
  ])("rejects %s before committing", async (_label, invalidValues) => {
    const repository = new FakeAbilityAllocationRepository();
    const input = {
      ...validInput(),
      ...invalidValues,
    } as AllocateAbilityPointsInput;

    await expect(
      allocateAbilityPoints(await contextFor("owner"), input, {
        abilityAllocations: repository,
      }),
    ).rejects.toMatchObject({ code: "INVALID_ALLOCATION" });
    expect(repository.commands).toHaveLength(0);
  });

  it("rejects an unknown ability code before committing", async () => {
    const repository = new FakeAbilityAllocationRepository();
    const input = {
      ...validInput(),
      charisma: 1,
    } as AllocateAbilityPointsInput;

    await expect(
      allocateAbilityPoints(await contextFor("owner"), input, {
        abilityAllocations: repository,
      }),
    ).rejects.toMatchObject({ code: "INVALID_ALLOCATION" });
    expect(repository.commands).toHaveLength(0);
  });

  it.each([
    ["", 7],
    ["run-1", -1],
    ["run-1", 1.5],
  ])("rejects an invalid run id or expected version", async (runId, expectedVersion) => {
    const repository = new FakeAbilityAllocationRepository();

    await expect(
      allocateAbilityPoints(
        await contextFor("owner"),
        validInput({ runId, expectedVersion }),
        { abilityAllocations: repository },
      ),
    ).rejects.toMatchObject({ code: "INVALID_ALLOCATION" });
    expect(repository.commands).toHaveLength(0);
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_PLAYABLE",
    "ACTIVITY_UNAVAILABLE",
    "STALE_STATE",
    "INVALID_ALLOCATION",
    "INSUFFICIENT_ABILITY_POINTS",
    "ABILITY_LIMIT_EXCEEDED",
    "COMMIT_FAILED",
  ] as const)("preserves the repository error code %s", async (code) => {
    const repository = new FakeAbilityAllocationRepository(code);

    await expect(
      allocateAbilityPoints(await contextFor("owner"), validInput(), {
        abilityAllocations: repository,
      }),
    ).rejects.toMatchObject({ code });
  });
});

class FakeAbilityAllocationRepository implements AbilityAllocationRepository {
  readonly commands: AllocateAbilityPointsCommand[] = [];

  constructor(
    private readonly errorCode?: AllocateAbilityPointsCommitError["code"],
  ) {}

  async allocateAbilityPoints(command: AllocateAbilityPointsCommand) {
    this.commands.push(structuredClone(command));
    if (this.errorCode) {
      throw new AllocateAbilityPointsCommitError(this.errorCode);
    }
    return { nextStateVersion: command.expectedVersion + 1 };
  }
}

function validInput(
  overrides: Partial<AllocateAbilityPointsInput> = {},
): AllocateAbilityPointsInput {
  return {
    runId: "run-1",
    planning: 1,
    talking: 2,
    expertise: 3,
    editing: 4,
    visual: 5,
    filming: 6,
    expectedVersion: 7,
    ...overrides,
  };
}

async function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
