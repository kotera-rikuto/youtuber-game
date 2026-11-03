import "server-only";

import { SupabaseAdvanceWeekCommitRepository } from "@/backend/infrastructure/supabase/repositories/supabase-advance-week-commit-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createAdvanceWeekCommitRepository(client: DatabaseClient) {
  return new SupabaseAdvanceWeekCommitRepository(client);
}

export function createTrustedAdvanceWeekCommitRepository() {
  return createAdvanceWeekCommitRepository(createTrustedSupabaseClient());
}
