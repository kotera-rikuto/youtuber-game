import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import type { OwnedGameRunRow } from "@/backend/infrastructure/supabase/mappers/game-run-mapper";

export type DatabaseClient = SupabaseClient<Database>;

export async function findOwnedRun(
  client: DatabaseClient,
  actorUserId: UseCaseContext["actorUserId"],
  runId: string,
  operation: string,
): Promise<OwnedGameRunRow | null> {
  const { data, error } = await client
    .from("game_runs")
    .select("id,user_id,rule_set_id,status")
    .eq("id", runId)
    .eq("user_id", actorUserId)
    .maybeSingle();

  if (error) {
    throw new RepositoryError("QUERY_FAILED", operation);
  }

  return data;
}

export function mapRepositoryData<T>(
  operation: string,
  mapper: () => T,
): T {
  try {
    return mapper();
  } catch {
    throw new RepositoryError("INVALID_DATA", operation);
  }
}
