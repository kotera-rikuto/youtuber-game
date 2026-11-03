import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import type {
  IdeaEvaluationResult,
  IdeaEvaluator,
} from "@/backend/application/ports/idea-evaluator";
import { createIdea } from "@/backend/application/use-cases/create-idea";
import { createIdeaTitle } from "@/backend/domain/game/idea-creation";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabaseCreateIdeaRepository } from "@/backend/infrastructure/supabase/repositories/supabase-create-idea-repository";
import { validateLocalIntegrationEnvironment } from "@/scripts/repository-integration-environment.js";

vi.mock("server-only", () => ({}));

const localEnvironment = validateLocalIntegrationEnvironment({
  url: process.env.SUPABASE_INTEGRATION_URL,
  publishableKey: process.env.SUPABASE_INTEGRATION_PUBLISHABLE_KEY,
  secretKey: process.env.SUPABASE_INTEGRATION_SECRET_KEY,
  databaseUrl: process.env.SUPABASE_INTEGRATION_DB_URL,
});
const clientOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
    detectSessionInUrl: false,
  },
} as const;

let serviceClient: SupabaseClient<Database>;

beforeAll(() => {
  serviceClient = createClient<Database>(
    localEnvironment.url,
    localEnvironment.secretKey,
    clientOptions,
  );
});

describe("createIdea integration", () => {
  it("stores an idea, completed evaluation, queue entry, and version atomically", async () => {
    const fixture = await startGameFixture("atomic");
    const ideas = new SupabaseCreateIdeaRepository(serviceClient);
    const evaluator = new FixedEvaluator({
      score: 91,
      status: "completed",
      model: "integration-model-2026-11-03",
      promptVersion: "integration-prompt-v1",
    });

    const result = await createIdea(
      fixture.context,
      {
        runId: fixture.runId,
        title: "  Integration idea  ",
        description: "Stored in the same transaction",
        expectedVersion: 0,
      },
      { ideas, evaluator },
    );

    expect(result).toEqual({
      ideaId: expect.stringMatching(/^[0-9a-f-]{36}$/),
      evaluationStatus: "completed",
    });
    expect(result).not.toHaveProperty("score");

    const [ideaResult, evaluationResult, queueResult, stateResult] =
      await Promise.all([
        serviceClient
          .from("player_ideas")
          .select("title,description,created_week")
          .eq("id", result.ideaId)
          .single(),
        serviceClient
          .from("idea_evaluations")
          .select("score,evaluation_status,model,prompt_version,evaluated_at")
          .eq("idea_id", result.ideaId)
          .single(),
        serviceClient
          .from("idea_queue_entries")
          .select("position")
          .eq("idea_id", result.ideaId)
          .single(),
        serviceClient
          .from("run_state")
          .select("state_version")
          .eq("run_id", fixture.runId)
          .single(),
      ]);

    expect(ideaResult.error).toBeNull();
    expect(ideaResult.data).toEqual({
      title: "Integration idea",
      description: "Stored in the same transaction",
      created_week: 1,
    });
    expect(evaluationResult.error).toBeNull();
    expect(evaluationResult.data).toMatchObject({
      score: 91,
      evaluation_status: "completed",
      model: "integration-model-2026-11-03",
      prompt_version: "integration-prompt-v1",
      evaluated_at: expect.any(String),
    });
    expect(queueResult.error).toBeNull();
    expect(queueResult.data).toEqual({ position: 1 });
    expect(stateResult.error).toBeNull();
    expect(stateResult.data).toEqual({ state_version: 1 });
  });

  it("serializes concurrent final-slot creation without exceeding the weekly limit", async () => {
    const fixture = await startGameFixture("concurrent");
    const ideas = new SupabaseCreateIdeaRepository(serviceClient);

    await ideas.commitCreateIdea({
      actorUserId: fixture.context.actorUserId,
      runId: fixture.runId,
      expectedVersion: 0,
      title: createIdeaTitle("Existing idea one"),
      description: null,
      evaluation: completedEvaluation,
    });
    await ideas.commitCreateIdea({
      actorUserId: fixture.context.actorUserId,
      runId: fixture.runId,
      expectedVersion: 1,
      title: createIdeaTitle("Existing idea two"),
      description: null,
      evaluation: completedEvaluation,
    });

    const evaluator = new TwoCallBarrierEvaluator(completedEvaluation);
    const attempts = await Promise.allSettled([
      createIdea(
        fixture.context,
        {
          runId: fixture.runId,
          title: "Concurrent candidate A",
          expectedVersion: 2,
        },
        { ideas, evaluator },
      ),
      createIdea(
        fixture.context,
        {
          runId: fixture.runId,
          title: "Concurrent candidate B",
          expectedVersion: 2,
        },
        { ideas, evaluator },
      ),
    ]);

    expect(evaluator.callCount).toBe(2);
    expect(
      attempts.filter((attempt) => attempt.status === "fulfilled"),
    ).toHaveLength(1);
    const rejected = attempts.find(
      (attempt): attempt is PromiseRejectedResult =>
        attempt.status === "rejected",
    );
    expect(rejected?.reason).toMatchObject({ code: "STALE_STATE" });

    const [ideaCount, queueEntries, state] = await Promise.all([
      serviceClient
        .from("player_ideas")
        .select("id", { count: "exact", head: true })
        .eq("run_id", fixture.runId)
        .eq("created_week", 1),
      serviceClient
        .from("idea_queue_entries")
        .select("position")
        .eq("run_id", fixture.runId)
        .order("position"),
      serviceClient
        .from("run_state")
        .select("state_version")
        .eq("run_id", fixture.runId)
        .single(),
    ]);

    expect(ideaCount.error).toBeNull();
    expect(ideaCount.count).toBe(3);
    expect(queueEntries.error).toBeNull();
    expect(queueEntries.data?.map((entry) => entry.position)).toEqual([1, 2, 3]);
    expect(state.error).toBeNull();
    expect(state.data?.state_version).toBe(3);
  });
});

const completedEvaluation: IdeaEvaluationResult = {
  score: 75,
  status: "completed",
  model: "integration-model",
  promptVersion: "integration-prompt-v1",
};

class FixedEvaluator implements IdeaEvaluator {
  constructor(private readonly evaluation: IdeaEvaluationResult) {}

  async evaluate(): Promise<IdeaEvaluationResult> {
    return structuredClone(this.evaluation);
  }
}

class TwoCallBarrierEvaluator implements IdeaEvaluator {
  callCount = 0;
  private readonly bothCallsStarted: Promise<void>;
  private releaseBothCalls!: () => void;

  constructor(private readonly evaluation: IdeaEvaluationResult) {
    this.bothCallsStarted = new Promise((resolve) => {
      this.releaseBothCalls = resolve;
    });
  }

  async evaluate(): Promise<IdeaEvaluationResult> {
    this.callCount += 1;
    if (this.callCount === 2) {
      this.releaseBothCalls();
    }
    await this.bothCallsStarted;
    return structuredClone(this.evaluation);
  }
}

async function startGameFixture(label: string): Promise<{
  context: UseCaseContext;
  runId: string;
}> {
  const email = `be019-${label}-${crypto.randomUUID()}@example.test`;
  const { data: userResult, error: userError } =
    await serviceClient.auth.admin.createUser({
      email,
      password: "BE-019-local-password",
      email_confirm: true,
    });
  if (userError) {
    throw new Error("Unable to create a BE-019 integration-test user.");
  }

  const context = await requireUseCaseContext({
    getVerifiedUser: async () => ({
      status: "authenticated",
      userId: userResult.user.id,
    }),
  });
  const { data: runId, error: startError } = await serviceClient.rpc(
    "commit_start_game",
    {
      p_actor_user_id: context.actorUserId,
      p_channel_name: `BE-019 ${label}`,
      p_posting_style: "mainstream",
    },
  );
  if (startError || !runId) {
    throw new Error("Unable to start a BE-019 integration-test game.");
  }

  return { context, runId };
}
