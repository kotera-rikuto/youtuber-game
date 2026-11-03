import "server-only";

import type { SelectWeeklyMainActionDependencies } from "@/backend/application/use-cases/select-weekly-main-action";
import { SupabaseWeeklyMainActionRepository } from "@/backend/infrastructure/supabase/repositories/supabase-weekly-main-action-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createSelectWeeklyMainActionDependencies(): SelectWeeklyMainActionDependencies {
  return {
    weeklyMainActions: new SupabaseWeeklyMainActionRepository(
      createTrustedSupabaseClient(),
    ),
  };
}
