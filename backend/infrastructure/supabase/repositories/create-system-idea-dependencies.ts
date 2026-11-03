import "server-only";

import { MathRandomSource } from "@/backend/infrastructure/random/math-random-source";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { SupabaseSystemIdeaRepository } from "@/backend/infrastructure/supabase/repositories/supabase-system-idea-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createSystemIdeaDependencies(
  client: DatabaseClient = createTrustedSupabaseClient(),
) {
  return {
    systemIdeas: new SupabaseSystemIdeaRepository(client),
    randomSource: new MathRandomSource(),
  };
}
