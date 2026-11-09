import "server-only";

import type {
  AbandonGameDependencies,
} from "@/backend/application/use-cases/abandon-game";
import type { RenameChannelDependencies } from "@/backend/application/use-cases/rename-channel";
import { SupabaseGameRunManagementRepository } from "@/backend/infrastructure/supabase/repositories/supabase-game-run-management-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createGameRunManagementDependencies():
  & AbandonGameDependencies
  & RenameChannelDependencies {
  const gameRuns = new SupabaseGameRunManagementRepository(
    createTrustedSupabaseClient(),
  );

  return { gameRuns };
}