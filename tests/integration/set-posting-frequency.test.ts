import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import { setPostingFrequency } from "@/backend/application/use-cases/set-posting-frequency";
import type { PostingFrequency } from "@/backend/domain/game/rules";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabasePostingFrequencyRepository } from "@/backend/infrastructure/supabase/repositories/supabase-posting-frequency-repository";
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

describe("setPostingFrequency integration", () => {
  it("sets 1, 3, and 7 from the run rule set and keeps the value until the next change", async () => {
    const fixture = await startGameFixture("frequencies");
    const repository = new SupabasePostingFrequencyRepository(serviceClient);
    const alternativeRuleSetId = await createAlternativeFrequencyRule(7);

    for (const [expectedVersion, videosPerWeek] of [
      [0, 1],
      [1, 3],
      [2, 7],
    ] as const) {
      await expect(
        setPostingFrequency(
          fixture.context,
          { runId: fixture.runId, videosPerWeek, expectedVersion },
          { postingFrequencies: repository },
        ),
      ).resolves.toEqual({
        videosPerWeek,
        nextStateVersion: expectedVersion + 1,
      });
    }

    const selectedAfterSeven = await readSelectedFrequency(fixture.runId);
    expect(selectedAfterSeven).toMatchObject({
      videosPerWeek: 7,
      stateVersion: 3,
    });
    expect(selectedAfterSeven.ruleSetId).toBe(fixture.ruleSetId);
    expect(selectedAfterSeven.ruleSetId).not.toBe(alternativeRuleSetId);

    const { error: unrelatedCommitError } = await serviceClient.rpc(
      "commit_create_idea",
      {
        p_actor_user_id: fixture.context.actorUserId,
        p_run_id: fixture.runId,
        p_title: "Frequency persistence integration check",
        p_expected_version: 3,
        p_score: 75,
        p_evaluation_status: "completed",
        p_model: "integration-model",
        p_prompt_version: "integration-prompt-v1",
      },
    );
    expect(unrelatedCommitError).toBeNull();

    await expect(readSelectedFrequency(fixture.runId)).resolves.toMatchObject({
      videosPerWeek: 7,
      stateVersion: 4,
    });

    await expect(
      setPostingFrequency(
        fixture.context,
        { runId: fixture.runId, videosPerWeek: 3, expectedVersion: 4 },
        { postingFrequencies: repository },
      ),
    ).resolves.toEqual({ videosPerWeek: 3, nextStateVersion: 5 });
    await expect(readSelectedFrequency(fixture.runId)).resolves.toMatchObject({
      videosPerWeek: 3,
      stateVersion: 5,
    });
  });

  it("rejects missing, foreign, finished, unavailable, and stale runs without partial updates", async () => {
    const owner = await startGameFixture("owner-checks");
    const otherOwner = await startGameFixture("other-owner");
    const finished = await startGameFixture("finished");
    const unavailable = await startGameFixture("unavailable");
    const repository = new SupabasePostingFrequencyRepository(serviceClient);

    await expect(
      setPostingFrequency(
        owner.context,
        {
          runId: crypto.randomUUID(),
          videosPerWeek: 3,
          expectedVersion: 0,
        },
        { postingFrequencies: repository },
      ),
    ).rejects.toMatchObject({ code: "RUN_NOT_FOUND" });

    await expect(
      setPostingFrequency(
        otherOwner.context,
        { runId: owner.runId, videosPerWeek: 3, expectedVersion: 0 },
        { postingFrequencies: repository },
      ),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });

    await expect(
      setPostingFrequency(
        owner.context,
        { runId: owner.runId, videosPerWeek: 7, expectedVersion: 99 },
        { postingFrequencies: repository },
      ),
    ).rejects.toMatchObject({ code: "STALE_STATE" });
    await expect(readSelectedFrequency(owner.runId)).resolves.toMatchObject({
      videosPerWeek: 1,
      stateVersion: 0,
    });

    const { error: finishError } = await serviceClient
      .from("game_runs")
      .update({ status: "game_over", completed_at: new Date().toISOString() })
      .eq("id", finished.runId);
    expect(finishError).toBeNull();
    await expect(
      setPostingFrequency(
        finished.context,
        { runId: finished.runId, videosPerWeek: 3, expectedVersion: 0 },
        { postingFrequencies: repository },
      ),
    ).rejects.toMatchObject({ code: "RUN_NOT_PLAYABLE" });

    await makeCurrentWeekUnavailable(unavailable);
    await expect(
      setPostingFrequency(
        unavailable.context,
        { runId: unavailable.runId, videosPerWeek: 3, expectedVersion: 0 },
        { postingFrequencies: repository },
      ),
    ).rejects.toMatchObject({ code: "ACTIVITY_UNAVAILABLE" });
    await expect(
      readSelectedFrequency(unavailable.runId),
    ).resolves.toMatchObject({ videosPerWeek: 1, stateVersion: 0 });
  });

  it("allows only one concurrent update for the same expected version", async () => {
    const fixture = await startGameFixture("concurrent");
    const repository = new SupabasePostingFrequencyRepository(serviceClient);

    const attempts = await Promise.allSettled([
      setPostingFrequency(
        fixture.context,
        { runId: fixture.runId, videosPerWeek: 3, expectedVersion: 0 },
        { postingFrequencies: repository },
      ),
      setPostingFrequency(
        fixture.context,
        { runId: fixture.runId, videosPerWeek: 7, expectedVersion: 0 },
        { postingFrequencies: repository },
      ),
    ]);

    const fulfilled = attempts.find(
      (attempt): attempt is PromiseFulfilledResult<{
        videosPerWeek: PostingFrequency;
        nextStateVersion: number;
      }> => attempt.status === "fulfilled",
    );
    const rejected = attempts.find(
      (attempt): attempt is PromiseRejectedResult =>
        attempt.status === "rejected",
    );
    expect(attempts.filter((attempt) => attempt.status === "fulfilled")).toHaveLength(
      1,
    );
    expect(rejected?.reason).toMatchObject({ code: "STALE_STATE" });
    expect(fulfilled?.value.nextStateVersion).toBe(1);

    const committed = await readSelectedFrequency(fixture.runId);
    expect(committed.stateVersion).toBe(1);
    expect(committed.videosPerWeek).toBe(fulfilled?.value.videosPerWeek);
  });

  it("does not expose the RPC to an authenticated database role", async () => {
    const fixture = await startGameFixture("authenticated-rpc");
    const authenticatedClient = createClient<Database>(
      localEnvironment.url,
      localEnvironment.publishableKey,
      clientOptions,
    );
    const { error: signInError } = await authenticatedClient.auth.signInWithPassword({
      email: fixture.email,
      password: fixture.password,
    });
    expect(signInError).toBeNull();

    const { data, error } = await authenticatedClient.rpc(
      "set_posting_frequency",
      {
        p_actor_user_id: fixture.context.actorUserId,
        p_run_id: fixture.runId,
        p_videos_per_week: 3,
        p_expected_version: 0,
      },
    );

    expect(data).toBeNull();
    expect(error).not.toBeNull();
    await expect(readSelectedFrequency(fixture.runId)).resolves.toMatchObject({
      videosPerWeek: 1,
      stateVersion: 0,
    });
  });
});

type GameFixture = {
  context: UseCaseContext;
  runId: string;
  ruleSetId: string;
  email: string;
  password: string;
};

async function startGameFixture(label: string): Promise<GameFixture> {
  const email = `be021-${label}-${crypto.randomUUID()}@example.test`;
  const password = "BE-021-local-password";
  const { data: userResult, error: userError } =
    await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
  if (userError) {
    throw new Error("Unable to create a BE-021 integration-test user.");
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
      p_channel_name: `BE-021 ${label}`,
      p_posting_style: "mainstream",
    },
  );
  if (startError || !runId) {
    throw new Error("Unable to start a BE-021 integration-test game.");
  }

  const { data: run, error: runError } = await serviceClient
    .from("game_runs")
    .select("rule_set_id")
    .eq("id", runId)
    .single();
  if (runError) {
    throw new Error("Unable to read the BE-021 integration-test game.");
  }

  return {
    context,
    runId,
    ruleSetId: run.rule_set_id,
    email,
    password,
  };
}

async function createAlternativeFrequencyRule(
  videosPerWeek: PostingFrequency,
): Promise<string> {
  const { data: ruleSet, error: ruleSetError } = await serviceClient
    .from("rule_sets")
    .insert({ version: `be021-${crypto.randomUUID()}` })
    .select("id")
    .single();
  if (ruleSetError) {
    throw new Error("Unable to create an alternate BE-021 rule set.");
  }

  const { error: frequencyError } = await serviceClient
    .from("posting_frequency_rules")
    .insert({
      rule_set_id: ruleSet.id,
      videos_per_week: videosPerWeek,
      view_multiplier: 9.9,
      energy_cost: 99,
      ability_points_awarded: 99,
    });
  if (frequencyError) {
    throw new Error("Unable to create an alternate BE-021 frequency rule.");
  }

  return ruleSet.id;
}

async function readSelectedFrequency(runId: string): Promise<{
  videosPerWeek: number;
  stateVersion: number;
  ruleSetId: string;
}> {
  const { data: state, error: stateError } = await serviceClient
    .from("run_state")
    .select("posting_frequency_rule_id,state_version")
    .eq("run_id", runId)
    .single();
  if (stateError) {
    throw new Error("Unable to read BE-021 run state.");
  }

  const { data: frequencyRule, error: frequencyError } = await serviceClient
    .from("posting_frequency_rules")
    .select("rule_set_id,videos_per_week")
    .eq("id", state.posting_frequency_rule_id)
    .single();
  if (frequencyError) {
    throw new Error("Unable to read the selected BE-021 frequency rule.");
  }

  return {
    videosPerWeek: frequencyRule.videos_per_week,
    stateVersion: state.state_version,
    ruleSetId: frequencyRule.rule_set_id,
  };
}

async function makeCurrentWeekUnavailable(fixture: GameFixture): Promise<void> {
  const { data: healthRule, error: healthRuleError } = await serviceClient
    .from("health_risk_rules")
    .select("id")
    .eq("rule_set_id", fixture.ruleSetId)
    .limit(1)
    .single();
  if (healthRuleError) {
    throw new Error("Unable to read a BE-021 health rule.");
  }

  const { error: weekError } = await serviceClient
    .from("run_state")
    .update({ current_week: 2 })
    .eq("run_id", fixture.runId);
  if (weekError) {
    throw new Error("Unable to move the BE-021 fixture to week two.");
  }

  const { error: conditionError } = await serviceClient
    .from("run_conditions")
    .insert({
      run_id: fixture.runId,
      health_risk_rule_id: healthRule.id,
      started_week: 1,
      duration_weeks: 1,
      unavailable_from_week: 2,
      unavailable_through_week: 2,
    });
  if (conditionError) {
    throw new Error("Unable to create a BE-021 unavailable condition.");
  }
}
