import "server-only";

import type { CreateIdeaDependencies } from "@/backend/application/use-cases/create-idea";
import { createOpenAIIdeaEvaluator } from "@/backend/infrastructure/openai/openai-idea-evaluator";
import { SupabaseCreateIdeaRepository } from "@/backend/infrastructure/supabase/repositories/supabase-create-idea-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createCreateIdeaDependencies(): CreateIdeaDependencies {
  return {
    ideas: new SupabaseCreateIdeaRepository(createTrustedSupabaseClient()),
    evaluator: createOpenAIIdeaEvaluator(),
  };
}
