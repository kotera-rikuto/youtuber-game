import "server-only";

import {
  SetPostingFrequencyCommitError,
  type PostingFrequencyRepository,
  type SetPostingFrequencyCommand,
  type SetPostingFrequencyCommitResult,
} from "@/backend/application/ports/posting-frequency-repository";
import {
  POSTING_FREQUENCIES,
  type PostingFrequency,
} from "@/backend/domain/game/rules";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabasePostingFrequencyRepository
  implements PostingFrequencyRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async setPostingFrequency(
    command: SetPostingFrequencyCommand,
  ): Promise<SetPostingFrequencyCommitResult> {
    const { data, error } = await this.client.rpc("set_posting_frequency", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_videos_per_week: command.videosPerWeek,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapSetPostingFrequencyRpcError(error.message);
    }

    return mapCommitResult(data);
  }
}

const postingFrequencyValues: ReadonlySet<unknown> = new Set(
  POSTING_FREQUENCIES,
);

function mapCommitResult(data: unknown): SetPostingFrequencyCommitResult {
  if (
    typeof data !== "object" ||
    data === null ||
    !("videosPerWeek" in data) ||
    !postingFrequencyValues.has(data.videosPerWeek) ||
    !("nextStateVersion" in data) ||
    !Number.isInteger(data.nextStateVersion) ||
    (data.nextStateVersion as number) < 1
  ) {
    throw new SetPostingFrequencyCommitError("COMMIT_FAILED");
  }

  return {
    videosPerWeek: data.videosPerWeek as PostingFrequency,
    nextStateVersion: data.nextStateVersion as number,
  };
}

const setPostingFrequencyErrorCodes = new Map<
  string,
  SetPostingFrequencyCommitError["code"]
>([
  ["SET_POSTING_FREQUENCY_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["SET_POSTING_FREQUENCY_FORBIDDEN", "FORBIDDEN"],
  ["SET_POSTING_FREQUENCY_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
  ["SET_POSTING_FREQUENCY_ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
  ["SET_POSTING_FREQUENCY_STALE_STATE", "STALE_STATE"],
  [
    "SET_POSTING_FREQUENCY_INVALID_POSTING_FREQUENCY",
    "INVALID_POSTING_FREQUENCY",
  ],
  ["SET_POSTING_FREQUENCY_RULE_UNAVAILABLE", "RULE_UNAVAILABLE"],
]);

function mapSetPostingFrequencyRpcError(
  message: string,
): SetPostingFrequencyCommitError {
  return new SetPostingFrequencyCommitError(
    setPostingFrequencyErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}
