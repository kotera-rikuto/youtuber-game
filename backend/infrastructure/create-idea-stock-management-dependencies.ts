import "server-only";

import type { DeleteIdeaDependencies } from "@/backend/application/use-cases/delete-idea";
import type { ReorderIdeaStockDependencies } from "@/backend/application/use-cases/reorder-idea-stock";
import { SupabaseIdeaStockManagementRepository } from "@/backend/infrastructure/supabase/repositories/supabase-idea-stock-management-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createIdeaStockManagementDependencies():
  & DeleteIdeaDependencies
  & ReorderIdeaStockDependencies {
  return {
    ideas: new SupabaseIdeaStockManagementRepository(
      createTrustedSupabaseClient(),
    ),
  };
}
