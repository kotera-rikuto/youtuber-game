import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { requireUseCaseContext } from "@/backend/application/auth/authentication";
import type { FatalAdvanceWeekCommitCommand } from "@/backend/application/ports/advance-week-commit-repository";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { createAdvanceWeekCommitRepository } from "@/backend/infrastructure/supabase/repositories/create-advance-week-commit-repository";
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

describe("advance-week commit repository integration", () => {
  it("returns one receipt and one side effect for simultaneous same-key calls", async () => {
    const email = `be029-${crypto.randomUUID()}@example.test`;
    const { data: createdUser, error: userError } =
      await serviceClient.auth.admin.createUser({
        email,
        password: "BE-029-local-password",
        email_confirm: true,
      });
    expect(userError).toBeNull();

    const actorUserId = createdUser.user?.id;
    if (!actorUserId) {
      throw new Error("Unable to create the BE-029 integration-test user.");
    }

    const { data: runId, error: startError } = await serviceClient.rpc(
      "commit_start_game",
      {
        p_actor_user_id: actorUserId,
        p_channel_name: "BE-029 Concurrent Commit",
        p_posting_style: "mainstream",
      },
    );
    expect(startError).toBeNull();
    if (!runId) {
      throw new Error("Unable to create the BE-029 integration-test run.");
    }

    const { data: actionRule, error: actionRuleError } = await serviceClient
      .from("action_rules")
      .select("id")
      .eq("rule_set_id", "00000000-0000-4000-8000-000000000001")
      .eq("action_code", "rest")
      .single();
    expect(actionRuleError).toBeNull();
    if (!actionRule) {
      throw new Error("The seeded rest action is unavailable.");
    }

    const { error: actionError } = await serviceClient
      .from("weekly_actions")
      .insert({
        run_id: runId,
        week_number: 1,
        action_rule_id: actionRule.id,
      });
    expect(actionError).toBeNull();

    const context = await requireUseCaseContext({
      getVerifiedUser: async () => ({
        status: "authenticated" as const,
        userId: actorUserId,
      }),
    });
    const command: FatalAdvanceWeekCommitCommand = {
      kind: "fatal_game_over",
      actorUserId: context.actorUserId,
      runId,
      attemptedWeek: 1,
      expectedVersion: 0,
      idempotencyKey: crypto.randomUUID(),
      reason: "death",
      calculatedEnergy: 0,
      calculatedFlameCount: 0,
    };
    const repository = createAdvanceWeekCommitRepository(serviceClient);

    const receipts = await Promise.all([
      repository.commitAdvanceWeek(command),
      repository.commitAdvanceWeek(command),
    ]);

    expect(receipts[0]).toEqual(receipts[1]);
    expect(receipts[0]).toMatchObject({
      outcome: "fatal_game_over",
      runId,
      reason: "death",
    });

    const [{ count: executionCount }, { count: terminationCount }, state] =
      await Promise.all([
        serviceClient
          .from("advance_week_executions")
          .select("idempotency_key", { count: "exact", head: true })
          .eq("idempotency_key", command.idempotencyKey),
        serviceClient
          .from("game_terminations")
          .select("id", { count: "exact", head: true })
          .eq("run_id", runId),
        serviceClient
          .from("run_state")
          .select("current_week,state_version")
          .eq("run_id", runId)
          .single(),
      ]);

    expect(executionCount).toBe(1);
    expect(terminationCount).toBe(1);
    expect(state.error).toBeNull();
    expect(state.data).toEqual({ current_week: 1, state_version: 0 });
  });
});
