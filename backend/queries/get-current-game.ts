import "server-only";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import { createAuthenticatedSupabaseRepositories } from "@/backend/infrastructure/supabase/repositories/create-repositories";
import {
  mapCurrentGameDTO,
  type CurrentGameDTO,
} from "@/backend/queries/game-result-dtos";
import { GameResultQueryError } from "@/backend/queries/game-result-query-error";
import type { GameResultQuerySource } from "@/backend/queries/game-result-source";

export async function getCurrentGameDTO(
  context: UseCaseContext,
  runId: string,
  source?: GameResultQuerySource,
): Promise<CurrentGameDTO> {
  try {
    const querySource = source ?? (await createAuthenticatedSupabaseRepositories()).gameRuns;
    const game = await querySource.findCurrentById({
      actorUserId: context.actorUserId,
      runId,
    });
    if (!game) {
      throw new GameResultQueryError("NOT_FOUND");
    }
    return mapCurrentGameDTO(game);
  } catch (error) {
    throw mapQueryError(error);
  }
}

function mapQueryError(error: unknown): GameResultQueryError {
  if (error instanceof GameResultQueryError) return error;
  if (error instanceof RepositoryError) {
    return new GameResultQueryError(
      error.code === "INVALID_DATA" ? "DATA_INTEGRITY_ERROR" : "QUERY_FAILED",
    );
  }
  return new GameResultQueryError("DATA_INTEGRITY_ERROR");
}
