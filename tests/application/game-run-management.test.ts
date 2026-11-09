import { describe, expect, it } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import {
  GameRunManagementCommitError,
  type GameRunManagementRepository,
} from "@/backend/application/ports/game-run-management-repository";
import {
  abandonGame,
  type AbandonGameInput,
} from "@/backend/application/use-cases/abandon-game";
import {
  renameChannel,
  type RenameChannelInput,
} from "@/backend/application/use-cases/rename-channel";

describe("abandonGame", () => {
  it("abandons a playing run through the verified owner context", async () => {
    const repository = new FakeGameRunManagementRepository();
    const context = await contextFor("owner");

    await expect(
      abandonGame(context, { runId: "run-1", expectedVersion: 4 }, { gameRuns: repository }),
    ).resolves.toEqual({ occurredWeek: 12 });
    expect(repository.abandonCommands).toEqual([
      { actorUserId: context.actorUserId, runId: "run-1", expectedVersion: 4 },
    ]);
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_ACTIVE",
    "STALE_STATE",
    "ALREADY_ABANDONED",
    "COMMIT_FAILED",
  ] as const)("keeps the stable error code %s", async (code) => {
    const repository = new FakeGameRunManagementRepository(code);

    await expect(
      abandonGame(await contextFor("owner"), { runId: "run-1", expectedVersion: 0 }, { gameRuns: repository }),
    ).rejects.toMatchObject({ code });
  });

  it.each([
    { runId: "", expectedVersion: 0 },
    { runId: "run-1", expectedVersion: -1 },
    { runId: "run-1", expectedVersion: 1.5 },
  ] as AbandonGameInput[])("rejects malformed input %j", async (input) => {
    const repository = new FakeGameRunManagementRepository();

    await expect(
      abandonGame(await contextFor("owner"), input, { gameRuns: repository }),
    ).rejects.toMatchObject({ code: "COMMIT_FAILED" });
    expect(repository.abandonCommands).toHaveLength(0);
  });
});

describe("renameChannel", () => {
  it("trims the name and increments the state version only through the repository", async () => {
    const repository = new FakeGameRunManagementRepository();
    const context = await contextFor("owner");

    await expect(
      renameChannel(
        context,
        { runId: "run-1", channelName: "  新しい名前  ", expectedVersion: 4 },
        { gameRuns: repository },
      ),
    ).resolves.toEqual({ channelName: "新しい名前", nextStateVersion: 5 });
    expect(repository.renameCommands).toEqual([
      {
        actorUserId: context.actorUserId,
        runId: "run-1",
        channelName: "新しい名前",
        expectedVersion: 4,
      },
    ]);
  });

  it.each(["", " \n\t ", null, 123])(
    "rejects a blank or non-string name: %j",
    async (channelName) => {
      const repository = new FakeGameRunManagementRepository();
      const input = {
        runId: "run-1",
        channelName,
        expectedVersion: 0,
      } as unknown as RenameChannelInput;

      await expect(
        renameChannel(await contextFor("owner"), input, { gameRuns: repository }),
      ).rejects.toMatchObject({ code: "INVALID_CHANNEL_NAME" });
      expect(repository.renameCommands).toHaveLength(0);
    },
  );

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_ACTIVE",
    "STALE_STATE",
    "COMMIT_FAILED",
  ] as const)("keeps the stable error code %s", async (code) => {
    const repository = new FakeGameRunManagementRepository(undefined, code);

    await expect(
      renameChannel(
        await contextFor("owner"),
        { runId: "run-1", channelName: "有効な名前", expectedVersion: 0 },
        { gameRuns: repository },
      ),
    ).rejects.toMatchObject({ code });
  });
});

class FakeGameRunManagementRepository implements GameRunManagementRepository {
  readonly abandonCommands: unknown[] = [];
  readonly renameCommands: unknown[] = [];

  constructor(
    private readonly abandonError?: GameRunManagementCommitError["code"],
    private readonly renameError?: GameRunManagementCommitError["code"],
  ) {}

  async abandonGame(command: Parameters<GameRunManagementRepository["abandonGame"]>[0]) {
    this.abandonCommands.push(structuredClone(command));
    if (this.abandonError) {
      throw new GameRunManagementCommitError(this.abandonError);
    }
    return { occurredWeek: 12 };
  }

  async renameChannel(command: Parameters<GameRunManagementRepository["renameChannel"]>[0]) {
    this.renameCommands.push(structuredClone(command));
    if (this.renameError) {
      throw new GameRunManagementCommitError(this.renameError);
    }
    return { channelName: command.channelName, nextStateVersion: command.expectedVersion + 1 };
  }
}

function contextFor(userId: string): Promise<UseCaseContext> {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}