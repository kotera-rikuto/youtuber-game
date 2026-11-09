import "server-only";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import { createAuthenticatedSupabaseRepositories } from "@/backend/infrastructure/supabase/repositories/create-repositories";
import {
  mapFinalResultDTO,
  type FinalResultDTO,
} from "@/backend/queries/game-result-dtos";
import { GameResultQueryError } from "@/backend/queries/game-result-query-error";
import type { GameResultQuerySource } from "@/backend/queries/game-result-source";

export async function getFinalResultDTO(
  context: UseCaseContext,
  runId: string,
  source?: GameResultQuerySource,
): Promise<FinalResultDTO> {
  try {
    const querySource = source ?? (await createAuthenticatedSupabaseRepositories()).gameRuns;
    const game = await querySource.findFinalById({
      actorUserId: context.actorUserId,
      runId,
    });
    if (!game) {
      throw new GameResultQueryError("NOT_FOUND");
    }
    if (game.status === "playing" || game.status === "stage_cleared") {
      throw new GameResultQueryError("INVALID_STATE");
    }
    return mapFinalResultDTO(game);
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
