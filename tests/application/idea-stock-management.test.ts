import { describe, expect, it } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import {
  IdeaStockManagementCommitError,
  type DeleteIdeaCommand,
  type IdeaStockManagementCommitErrorCode,
  type IdeaStockManagementRepository,
  type ReorderIdeaStockCommand,
} from "@/backend/application/ports/idea-stock-management-repository";
import { deleteIdea } from "@/backend/application/use-cases/delete-idea";
import { reorderIdeaStock } from "@/backend/application/use-cases/reorder-idea-stock";

describe("deleteIdea", () => {
  it("commits the verified actor and optimistic-lock version", async () => {
    const repository = new FakeIdeaStockManagementRepository();
    const context = await contextFor("verified-owner");

    await deleteIdea(
      context,
      {
        runId: "run-1",
        ideaId: "idea-2",
        expectedVersion: 7,
      },
      { ideas: repository },
    );

    expect(repository.deleteCommands).toEqual([
      {
        actorUserId: context.actorUserId,
        runId: "run-1",
        ideaId: "idea-2",
        expectedVersion: 7,
      },
    ]);
  });

  it("does not accept a forged owner from the input object", async () => {
    const repository = new FakeIdeaStockManagementRepository();
    const context = await contextFor("verified-owner");

    await deleteIdea(
      context,
      {
        runId: "run-1",
        ideaId: "idea-1",
        expectedVersion: 1,
        userId: "forged-owner",
      } as Parameters<typeof deleteIdea>[1],
      { ideas: repository },
    );

    expect(repository.deleteCommands[0]?.actorUserId).toBe(
      context.actorUserId,
    );
    expect(repository.deleteCommands[0]).not.toHaveProperty("userId");
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_PLAYABLE",
    "ACTIVITY_UNAVAILABLE",
    "STALE_STATE",
    "IDEA_NOT_FOUND",
    "IDEA_ALREADY_POSTED",
    "IDEA_ALREADY_DELETED",
    "COMMIT_FAILED",
  ] as const)("maps the repository rejection: %s", async (code) => {
    const repository = new FakeIdeaStockManagementRepository({
      deleteError: code,
    });

    await expect(
      deleteIdea(
        await contextFor("owner"),
        { runId: "run-1", ideaId: "idea-1", expectedVersion: 2 },
        { ideas: repository },
      ),
    ).rejects.toMatchObject({ code });
  });
});

describe("reorderIdeaStock", () => {
  it("commits the complete order with the verified actor", async () => {
    const repository = new FakeIdeaStockManagementRepository();
    const context = await contextFor("verified-owner");

    await reorderIdeaStock(
      context,
      {
        runId: "run-1",
        orderedIdeaIds: ["idea-3", "idea-1", "idea-2"],
        expectedVersion: 8,
      },
      { ideas: repository },
    );

    expect(repository.reorderCommands).toEqual([
      {
        actorUserId: context.actorUserId,
        runId: "run-1",
        orderedIdeaIds: ["idea-3", "idea-1", "idea-2"],
        expectedVersion: 8,
      },
    ]);
  });

  it("rejects duplicate IDs before the repository boundary", async () => {
    const repository = new FakeIdeaStockManagementRepository();

    await expect(
      reorderIdeaStock(
        await contextFor("owner"),
        {
          runId: "run-1",
          orderedIdeaIds: ["idea-1", "idea-1"],
          expectedVersion: 3,
        },
        { ideas: repository },
      ),
    ).rejects.toMatchObject({ code: "INVALID_IDEA_ORDER" });
    expect(repository.reorderCommands).toHaveLength(0);
  });

  it("allows an empty order so the repository can validate an empty stock", async () => {
    const repository = new FakeIdeaStockManagementRepository();

    await expect(
      reorderIdeaStock(
        await contextFor("owner"),
        { runId: "run-1", orderedIdeaIds: [], expectedVersion: 0 },
        { ideas: repository },
      ),
    ).resolves.toBeUndefined();
    expect(repository.reorderCommands[0]?.orderedIdeaIds).toEqual([]);
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_PLAYABLE",
    "ACTIVITY_UNAVAILABLE",
    "STALE_STATE",
    "INVALID_IDEA_ORDER",
    "COMMIT_FAILED",
  ] as const)("maps the repository rejection: %s", async (code) => {
    const repository = new FakeIdeaStockManagementRepository({
      reorderError: code,
    });

    await expect(
      reorderIdeaStock(
        await contextFor("owner"),
        {
          runId: "run-1",
          orderedIdeaIds: ["idea-2", "idea-1"],
          expectedVersion: 4,
        },
        { ideas: repository },
      ),
    ).rejects.toMatchObject({ code });
  });
});

class FakeIdeaStockManagementRepository
  implements IdeaStockManagementRepository
{
  readonly deleteCommands: DeleteIdeaCommand[] = [];
  readonly reorderCommands: ReorderIdeaStockCommand[] = [];

  constructor(
    private readonly errors: {
      deleteError?: IdeaStockManagementCommitErrorCode;
      reorderError?: IdeaStockManagementCommitErrorCode;
    } = {},
  ) {}

  async deleteIdea(command: DeleteIdeaCommand): Promise<void> {
    this.deleteCommands.push(structuredClone(command));
    if (this.errors.deleteError) {
      throw new IdeaStockManagementCommitError(this.errors.deleteError);
    }
  }

  async reorderIdeaStock(command: ReorderIdeaStockCommand): Promise<void> {
    this.reorderCommands.push(structuredClone(command));
    if (this.errors.reorderError) {
      throw new IdeaStockManagementCommitError(this.errors.reorderError);
    }
  }
}

function contextFor(userId: string): Promise<UseCaseContext> {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
