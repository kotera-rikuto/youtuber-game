import "server-only";

import type { SetPostingFrequencyDependencies } from "@/backend/application/use-cases/set-posting-frequency";
import { SupabasePostingFrequencyRepository } from "@/backend/infrastructure/supabase/repositories/supabase-posting-frequency-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createSetPostingFrequencyDependencies(): SetPostingFrequencyDependencies {
  return {
    postingFrequencies: new SupabasePostingFrequencyRepository(
      createTrustedSupabaseClient(),
    ),
  };
}
