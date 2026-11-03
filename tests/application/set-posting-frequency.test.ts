import { describe, expect, it } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import {
  SetPostingFrequencyCommitError,
  type PostingFrequencyRepository,
  type SetPostingFrequencyCommand,
} from "@/backend/application/ports/posting-frequency-repository";
import {
  setPostingFrequency,
  type SetPostingFrequencyInput,
} from "@/backend/application/use-cases/set-posting-frequency";

describe("setPostingFrequency", () => {
  it.each([1, 3, 7] as const)(
    "sets a posting frequency of %i video(s) per week",
    async (videosPerWeek) => {
      const repository = new FakePostingFrequencyRepository();
      const context = await contextFor("verified-owner");

      await expect(
        setPostingFrequency(
          context,
          { runId: "run-1", videosPerWeek, expectedVersion: 4 },
          { postingFrequencies: repository },
        ),
      ).resolves.toEqual({ videosPerWeek, nextStateVersion: 5 });
      expect(repository.commands).toEqual([
        {
          actorUserId: context.actorUserId,
          runId: "run-1",
          videosPerWeek,
          expectedVersion: 4,
        },
      ]);
    },
  );

  it.each([0, 2, 5, -1, 1.5, "3", null])(
    "rejects an unsupported runtime frequency before committing: %j",
    async (videosPerWeek) => {
      const repository = new FakePostingFrequencyRepository();
      const input = {
        runId: "run-1",
        videosPerWeek,
        expectedVersion: 4,
      } as unknown as SetPostingFrequencyInput;

      await expect(
        setPostingFrequency(await contextFor("owner"), input, {
          postingFrequencies: repository,
        }),
      ).rejects.toMatchObject({ code: "INVALID_POSTING_FREQUENCY" });
      expect(repository.commands).toHaveLength(0);
    },
  );

  it("uses only the verified context as the owner", async () => {
    const repository = new FakePostingFrequencyRepository();
    const context = await contextFor("verified-owner");
    const input = {
      runId: "run-1",
      videosPerWeek: 3,
      expectedVersion: 4,
      actorUserId: "forged-owner",
    } as SetPostingFrequencyInput;

    await setPostingFrequency(context, input, {
      postingFrequencies: repository,
    });

    expect(repository.commands[0]?.actorUserId).toBe(context.actorUserId);
    expect(repository.commands[0]).not.toHaveProperty("userId");
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_PLAYABLE",
    "ACTIVITY_UNAVAILABLE",
    "STALE_STATE",
    "INVALID_POSTING_FREQUENCY",
    "RULE_UNAVAILABLE",
    "COMMIT_FAILED",
  ] as const)("maps the repository rejection: %s", async (code) => {
    const repository = new FakePostingFrequencyRepository(code);

    await expect(
      setPostingFrequency(
        await contextFor("owner"),
        { runId: "run-1", videosPerWeek: 7, expectedVersion: 4 },
        { postingFrequencies: repository },
      ),
    ).rejects.toMatchObject({ code });
  });
});

class FakePostingFrequencyRepository implements PostingFrequencyRepository {
  readonly commands: SetPostingFrequencyCommand[] = [];

  constructor(
    private readonly errorCode?: SetPostingFrequencyCommitError["code"],
  ) {}

  async setPostingFrequency(command: SetPostingFrequencyCommand) {
    this.commands.push(structuredClone(command));
    if (this.errorCode) {
      throw new SetPostingFrequencyCommitError(this.errorCode);
    }

    return {
      videosPerWeek: command.videosPerWeek,
      nextStateVersion: command.expectedVersion + 1,
    };
  }
}

function contextFor(userId: string): Promise<UseCaseContext> {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
