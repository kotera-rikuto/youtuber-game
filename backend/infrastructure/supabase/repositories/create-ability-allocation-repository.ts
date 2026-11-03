import "server-only";

import { SupabaseAbilityAllocationRepository } from "@/backend/infrastructure/supabase/repositories/supabase-ability-allocation-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createAbilityAllocationRepository(client: DatabaseClient) {
  return new SupabaseAbilityAllocationRepository(client);
}

export function createTrustedAbilityAllocationRepository() {
  return createAbilityAllocationRepository(createTrustedSupabaseClient());
}
