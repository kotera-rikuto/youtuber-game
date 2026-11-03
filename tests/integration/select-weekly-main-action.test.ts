import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import { selectWeeklyMainAction } from "@/backend/application/use-cases/select-weekly-main-action";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabaseWeeklyMainActionRepository } from "@/backend/infrastructure/supabase/repositories/supabase-weekly-main-action-repository";
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

describe("selectWeeklyMainAction integration", () => {
  it("inserts and replaces one current-week row without applying effects", async () => {
    const fixture = await startGameFixture("replace");
    const weeklyMainActions = new SupabaseWeeklyMainActionRepository(
      serviceClient,
    );

    await expect(
      selectWeeklyMainAction(
        fixture.context,
        {
          runId: fixture.runId,
          action: "part_time_job",
          expectedVersion: 0,
        },
        { weeklyMainActions },
      ),
    ).resolves.toEqual({
      action: "part_time_job",
      weekNumber: 1,
      stateVersion: 1,
    });

    await expect(
      selectWeeklyMainAction(
        fixture.context,
        { runId: fixture.runId, action: "rest", expectedVersion: 1 },
        { weeklyMainActions },
      ),
    ).resolves.toEqual({
      action: "rest",
      weekNumber: 1,
      stateVersion: 2,
    });

    const [actions, state] = await Promise.all([
      serviceClient
        .from("weekly_actions")
        .select("action_rule_id")
        .eq("run_id", fixture.runId),
      serviceClient
        .from("run_state")
        .select("cash,energy,state_version")
        .eq("run_id", fixture.runId)
        .single(),
    ]);

    expect(actions.error).toBeNull();
    expect(actions.data).toHaveLength(1);
    const actionRule = await serviceClient
      .from("action_rules")
      .select("action_code")
      .eq("id", actions.data?.[0]?.action_rule_id ?? "")
      .single();
    expect(actionRule.error).toBeNull();
    expect(actionRule.data?.action_code).toBe("rest");
    expect(state.error).toBeNull();
    expect(state.data).toEqual({
      cash: 100_000,
      energy: 100,
      state_version: 2,
    });
  });

  it("uses persistent unlock history after subscribers have fallen", async () => {
    const fixture = await startGameFixture("persistent-unlock");
    const weeklyMainActions = new SupabaseWeeklyMainActionRepository(
      serviceClient,
    );
    const featureRule = await serviceClient
      .from("feature_rules")
      .select("id")
      .eq("feature_code", "collaboration")
      .single();
    if (featureRule.error || !featureRule.data) {
      throw new Error("Unable to load the collaboration feature rule.");
    }

    const unlock = await serviceClient.from("run_feature_unlocks").insert({
      run_id: fixture.runId,
      feature_rule_id: featureRule.data.id,
      unlocked_week: 1,
      active_from_week: 1,
    });
    if (unlock.error) {
      throw new Error("Unable to create the collaboration unlock fixture.");
    }

    await expect(
      selectWeeklyMainAction(
        fixture.context,
        {
          runId: fixture.runId,
          action: "collaboration",
          expectedVersion: 0,
        },
        { weeklyMainActions },
      ),
    ).resolves.toMatchObject({ action: "collaboration", stateVersion: 1 });
  });

  it("serializes concurrent selections so one stale writer loses", async () => {
    const fixture = await startGameFixture("concurrent");
    const weeklyMainActions = new SupabaseWeeklyMainActionRepository(
      serviceClient,
    );

    const attempts = await Promise.allSettled([
      weeklyMainActions.selectWeeklyMainAction({
        actorUserId: fixture.context.actorUserId,
        runId: fixture.runId,
        action: "part_time_job",
        expectedVersion: 0,
      }),
      weeklyMainActions.selectWeeklyMainAction({
        actorUserId: fixture.context.actorUserId,
        runId: fixture.runId,
        action: "rest",
        expectedVersion: 0,
      }),
    ]);

    expect(
      attempts.filter((attempt) => attempt.status === "fulfilled"),
    ).toHaveLength(1);
    const rejected = attempts.find(
      (attempt): attempt is PromiseRejectedResult =>
        attempt.status === "rejected",
    );
    expect(rejected?.reason).toMatchObject({ code: "STALE_STATE" });

    const [actions, state] = await Promise.all([
      serviceClient
        .from("weekly_actions")
        .select("id", { count: "exact", head: true })
        .eq("run_id", fixture.runId),
      serviceClient
        .from("run_state")
        .select("state_version")
        .eq("run_id", fixture.runId)
        .single(),
    ]);
    expect(actions.error).toBeNull();
    expect(actions.count).toBe(1);
    expect(state.error).toBeNull();
    expect(state.data?.state_version).toBe(1);
  });

  it("rejects a different authenticated owner", async () => {
    const owner = await startGameFixture("owner");
    const other = await startGameFixture("other");
    const weeklyMainActions = new SupabaseWeeklyMainActionRepository(
      serviceClient,
    );

    await expect(
      weeklyMainActions.selectWeeklyMainAction({
        actorUserId: other.context.actorUserId,
        runId: owner.runId,
        action: "rest",
        expectedVersion: 0,
      }),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
  });
});

async function startGameFixture(label: string): Promise<{
  context: UseCaseContext;
  runId: string;
}> {
  const { data: userResult, error: userError } =
    await serviceClient.auth.admin.createUser({
      email: `be024-${label}-${crypto.randomUUID()}@example.test`,
      password: "BE-024-local-password",
      email_confirm: true,
    });
  if (userError) {
    throw new Error("Unable to create a BE-024 integration-test user.");
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
      p_channel_name: `BE-024 ${label}`,
      p_posting_style: "mainstream",
    },
  );
  if (startError || !runId) {
    throw new Error("Unable to start a BE-024 integration-test game.");
  }

  return { context, runId };
}
