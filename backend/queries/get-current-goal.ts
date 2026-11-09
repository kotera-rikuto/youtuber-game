import "server-only";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import { createAuthenticatedSupabaseRepositories } from "@/backend/infrastructure/supabase/repositories/create-repositories";
import {
  mapCurrentGoalDTO,
  type CurrentGoalDTO,
} from "@/backend/queries/game-result-dtos";
import { GameResultQueryError } from "@/backend/queries/game-result-query-error";
import type { GameResultQuerySource } from "@/backend/queries/game-result-source";

export async function getCurrentGoalDTO(
  context: UseCaseContext,
  runId: string,
  source?: GameResultQuerySource,
): Promise<CurrentGoalDTO | null> {
  try {
    const querySource = source ?? (await createAuthenticatedSupabaseRepositories()).gameRuns;
    const game = await querySource.findCurrentById({
      actorUserId: context.actorUserId,
      runId,
    });
    if (!game) {
      throw new GameResultQueryError("NOT_FOUND");
    }
    if (game.currentGoal && game.currentState.currentWeek > game.currentGoal.deadlineWeek) {
      throw new GameResultQueryError("INVALID_STATE");
    }
    return mapCurrentGoalDTO(game);
  } catch (error) {
    if (error instanceof GameResultQueryError) throw error;
    if (error instanceof RepositoryError) {
      throw new GameResultQueryError(
        error.code === "INVALID_DATA" ? "DATA_INTEGRITY_ERROR" : "QUERY_FAILED",
      );
    }
    throw new GameResultQueryError("DATA_INTEGRITY_ERROR");
  }
}
