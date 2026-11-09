import "server-only";

import { createReadOnlyClient } from "@/lib/supabase/server";

import { SupabaseGameRunRepository } from "@/backend/infrastructure/supabase/repositories/supabase-game-run-repository";
import { SupabaseGameRunManagementRepository } from "@/backend/infrastructure/supabase/repositories/supabase-game-run-management-repository";
import { SupabaseIdeaStockRepository } from "@/backend/infrastructure/supabase/repositories/supabase-idea-stock-repository";
import { SupabaseRuleRepository } from "@/backend/infrastructure/supabase/repositories/supabase-rule-repository";
import { SupabaseWeekResultRepository } from "@/backend/infrastructure/supabase/repositories/supabase-week-result-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createSupabaseRepositories(client: DatabaseClient) {
  return {
    gameRuns: new SupabaseGameRunRepository(client),
    gameRunManagement: new SupabaseGameRunManagementRepository(client),
    ideaStock: new SupabaseIdeaStockRepository(client),
    rules: new SupabaseRuleRepository(client),
    weekResults: new SupabaseWeekResultRepository(client),
  };
}

export async function createAuthenticatedSupabaseRepositories() {
  const client = await createReadOnlyClient();
  return createSupabaseRepositories(client);
}

export function createTrustedSupabaseRepositories() {
  return createSupabaseRepositories(createTrustedSupabaseClient());
}
