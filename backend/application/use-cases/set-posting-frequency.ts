import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  SetPostingFrequencyCommitError,
  type PostingFrequencyRepository,
} from "@/backend/application/ports/posting-frequency-repository";
import {
  POSTING_FREQUENCIES,
  type PostingFrequency,
} from "@/backend/domain/game/rules";

export type SetPostingFrequencyInput = {
  runId: string;
  videosPerWeek: PostingFrequency;
  expectedVersion: number;
};

export type SetPostingFrequencyResult = {
  videosPerWeek: PostingFrequency;
  nextStateVersion: number;
};

export type SetPostingFrequencyErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "INVALID_POSTING_FREQUENCY"
  | "RULE_UNAVAILABLE"
  | "COMMIT_FAILED";

export class SetPostingFrequencyError extends Error {
  constructor(readonly code: SetPostingFrequencyErrorCode) {
    super("投稿頻度を変更できませんでした。");
    this.name = "SetPostingFrequencyError";
  }
}

export type SetPostingFrequencyDependencies = {
  postingFrequencies: PostingFrequencyRepository;
};

const postingFrequencyValues: ReadonlySet<unknown> = new Set(
  POSTING_FREQUENCIES,
);

export async function setPostingFrequency(
  context: UseCaseContext,
  input: SetPostingFrequencyInput,
  dependencies: SetPostingFrequencyDependencies,
): Promise<SetPostingFrequencyResult> {
  if (!postingFrequencyValues.has(input.videosPerWeek)) {
    throw new SetPostingFrequencyError("INVALID_POSTING_FREQUENCY");
  }

  try {
    return await dependencies.postingFrequencies.setPostingFrequency({
      actorUserId: context.actorUserId,
      runId: input.runId,
      videosPerWeek: input.videosPerWeek,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof SetPostingFrequencyCommitError) {
      throw new SetPostingFrequencyError(error.code);
    }
    throw error;
  }
}
