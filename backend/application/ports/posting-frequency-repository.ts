import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { PostingFrequency } from "@/backend/domain/game/rules";

export type SetPostingFrequencyCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  videosPerWeek: PostingFrequency;
  expectedVersion: number;
};

export type SetPostingFrequencyCommitResult = {
  videosPerWeek: PostingFrequency;
  nextStateVersion: number;
};

export type SetPostingFrequencyCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "INVALID_POSTING_FREQUENCY"
  | "RULE_UNAVAILABLE"
  | "COMMIT_FAILED";

export class SetPostingFrequencyCommitError extends Error {
  constructor(readonly code: SetPostingFrequencyCommitErrorCode) {
    super("The posting frequency could not be set.");
    this.name = "SetPostingFrequencyCommitError";
  }
}

export interface PostingFrequencyRepository {
  setPostingFrequency(
    command: SetPostingFrequencyCommand,
  ): Promise<SetPostingFrequencyCommitResult>;
}
