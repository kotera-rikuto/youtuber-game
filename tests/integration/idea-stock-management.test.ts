import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import type { IdeaEvaluationResult } from "@/backend/application/ports/idea-evaluator";
import { deleteIdea } from "@/backend/application/use-cases/delete-idea";
import { reorderIdeaStock } from "@/backend/application/use-cases/reorder-idea-stock";
import { createIdeaTitle } from "@/backend/domain/game/idea-creation";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabaseCreateIdeaRepository } from "@/backend/infrastructure/supabase/repositories/supabase-create-idea-repository";
import { SupabaseIdeaStockManagementRepository } from "@/backend/infrastructure/supabase/repositories/supabase-idea-stock-management-repository";
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

describe("idea stock management integration", () => {
  it("soft-deletes a pending idea, preserves its source, and compacts the queue", async () => {
    const fixture = await createStockFixture("delete", 3);
    const ideas = new SupabaseIdeaStockManagementRepository(serviceClient);

    await deleteIdea(
      fixture.context,
      {
        runId: fixture.runId,
        ideaId: fixture.ideaIds[1]!,
        expectedVersion: 3,
      },
      { ideas },
    );

    const [sourceResult, queueResult, weeklyCountResult, stateResult] =
      await Promise.all([
        serviceClient
          .from("player_ideas")
          .select("id,created_week,deleted_at")
          .eq("id", fixture.ideaIds[1]!)
          .single(),
        serviceClient
          .from("idea_queue_entries")
          .select("idea_id,position")
          .eq("run_id", fixture.runId)
          .order("position"),
        serviceClient
          .from("player_ideas")
          .select("id", { count: "exact", head: true })
          .eq("run_id", fixture.runId)
          .eq("created_week", 1),
        serviceClient
          .from("run_state")
          .select("state_version")
          .eq("run_id", fixture.runId)
          .single(),
      ]);

    expect(sourceResult.error).toBeNull();
    expect(sourceResult.data).toMatchObject({
      id: fixture.ideaIds[1],
      created_week: 1,
      deleted_at: expect.any(String),
    });
    expect(queueResult.error).toBeNull();
    expect(queueResult.data).toEqual([
      { idea_id: fixture.ideaIds[0], position: 1 },
      { idea_id: fixture.ideaIds[2], position: 2 },
    ]);
    expect(weeklyCountResult.error).toBeNull();
    expect(weeklyCountResult.count).toBe(3);
    expect(stateResult.data).toEqual({ state_version: 4 });

    await expect(
      deleteIdea(
        fixture.context,
        {
          runId: fixture.runId,
          ideaId: fixture.ideaIds[1]!,
          expectedVersion: 4,
        },
        { ideas },
      ),
    ).rejects.toMatchObject({ code: "IDEA_ALREADY_DELETED" });
  });

  it("does not expose an idea belonging to another run", async () => {
    const ownerFixture = await createStockFixture("owner", 1);
    const otherFixture = await createStockFixture("other", 1);
    const ideas = new SupabaseIdeaStockManagementRepository(serviceClient);

    await expect(
      deleteIdea(
        ownerFixture.context,
        {
          runId: ownerFixture.runId,
          ideaId: otherFixture.ideaIds[0]!,
          expectedVersion: 1,
        },
        { ideas },
      ),
    ).rejects.toMatchObject({ code: "IDEA_NOT_FOUND" });

    const otherIdea = await serviceClient
      .from("player_ideas")
      .select("deleted_at")
      .eq("id", otherFixture.ideaIds[0]!)
      .single();
    expect(otherIdea.data?.deleted_at).toBeNull();
  });

  it("rejects stale and activity-unavailable deletion without changing state", async () => {
    const fixture = await createStockFixture("delete-guards", 1);
    const ideas = new SupabaseIdeaStockManagementRepository(serviceClient);

    await expect(
      deleteIdea(
        fixture.context,
        {
          runId: fixture.runId,
          ideaId: fixture.ideaIds[0]!,
          expectedVersion: 0,
        },
        { ideas },
      ),
    ).rejects.toMatchObject({ code: "STALE_STATE" });

    await addCurrentActivityUnavailableCondition(fixture.runId);

    await expect(
      deleteIdea(
        fixture.context,
        {
          runId: fixture.runId,
          ideaId: fixture.ideaIds[0]!,
          expectedVersion: 1,
        },
        { ideas },
      ),
    ).rejects.toMatchObject({ code: "ACTIVITY_UNAVAILABLE" });

    const [ideaResult, queueResult, stateResult] = await Promise.all([
      serviceClient
        .from("player_ideas")
        .select("deleted_at")
        .eq("id", fixture.ideaIds[0]!)
        .single(),
      serviceClient
        .from("idea_queue_entries")
        .select("position")
        .eq("idea_id", fixture.ideaIds[0]!)
        .single(),
      serviceClient
        .from("run_state")
        .select("state_version")
        .eq("run_id", fixture.runId)
        .single(),
    ]);
    expect(ideaResult.data?.deleted_at).toBeNull();
    expect(queueResult.data?.position).toBe(1);
    expect(stateResult.data?.state_version).toBe(1);
  });

  it("reorders the complete queue without intermediate unique collisions", async () => {
    const fixture = await createStockFixture("reorder", 3);
    const ideas = new SupabaseIdeaStockManagementRepository(serviceClient);
    const reversedIds = fixture.ideaIds.toReversed();

    await reorderIdeaStock(
      fixture.context,
      {
        runId: fixture.runId,
        orderedIdeaIds: reversedIds,
        expectedVersion: 3,
      },
      { ideas },
    );

    const [queueResult, stateResult] = await Promise.all([
      serviceClient
        .from("idea_queue_entries")
        .select("idea_id,position")
        .eq("run_id", fixture.runId)
        .order("position"),
      serviceClient
        .from("run_state")
        .select("state_version")
        .eq("run_id", fixture.runId)
        .single(),
    ]);
    expect(queueResult.error).toBeNull();
    expect(queueResult.data).toEqual(
      reversedIds.map((ideaId, index) => ({
        idea_id: ideaId,
        position: index + 1,
      })),
    );
    expect(stateResult.data?.state_version).toBe(4);
  });

  it.each([
    ["missing", (ids: string[]) => ids.slice(0, 2)],
    ["extra", (ids: string[]) => [...ids, crypto.randomUUID()]],
    ["duplicate", (ids: string[]) => [ids[0]!, ids[0]!, ids[2]!]],
  ])("rejects a %s ID order without partially updating the queue", async (_, order) => {
    const fixture = await createStockFixture(`invalid-${_}`, 3);
    const ideas = new SupabaseIdeaStockManagementRepository(serviceClient);

    await expect(
      reorderIdeaStock(
        fixture.context,
        {
          runId: fixture.runId,
          orderedIdeaIds: order(fixture.ideaIds),
          expectedVersion: 3,
        },
        { ideas },
      ),
    ).rejects.toMatchObject({ code: "INVALID_IDEA_ORDER" });

    const [queueResult, stateResult] = await Promise.all([
      serviceClient
        .from("idea_queue_entries")
        .select("idea_id,position")
        .eq("run_id", fixture.runId)
        .order("position"),
      serviceClient
        .from("run_state")
        .select("state_version")
        .eq("run_id", fixture.runId)
        .single(),
    ]);
    expect(queueResult.data).toEqual(
      fixture.ideaIds.map((ideaId, index) => ({
        idea_id: ideaId,
        position: index + 1,
      })),
    );
    expect(stateResult.data?.state_version).toBe(3);
  });

  it("rejects another run's ID from a reorder without exposing it", async () => {
    const ownerFixture = await createStockFixture("reorder-owner", 2);
    const otherFixture = await createStockFixture("reorder-other", 1);
    const ideas = new SupabaseIdeaStockManagementRepository(serviceClient);

    await expect(
      reorderIdeaStock(
        ownerFixture.context,
        {
          runId: ownerFixture.runId,
          orderedIdeaIds: [
            ownerFixture.ideaIds[0]!,
            otherFixture.ideaIds[0]!,
          ],
          expectedVersion: 2,
        },
        { ideas },
      ),
    ).rejects.toMatchObject({ code: "INVALID_IDEA_ORDER" });
  });
});

const completedEvaluation: IdeaEvaluationResult = {
  score: 75,
  status: "completed",
  model: "be020-integration-model",
  promptVersion: "be020-integration-v1",
};

async function createStockFixture(
  label: string,
  ideaCount: number,
): Promise<{
  context: UseCaseContext;
  runId: string;
  ideaIds: string[];
}> {
  const email = `be020-${label}-${crypto.randomUUID()}@example.test`;
  const { data: userResult, error: userError } =
    await serviceClient.auth.admin.createUser({
      email,
      password: "BE-020-local-password",
      email_confirm: true,
    });
  if (userError) {
    throw new Error("Unable to create a BE-020 integration-test user.");
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
      p_channel_name: `BE-020 ${label}`,
      p_posting_style: "mainstream",
    },
  );
  if (startError || !runId) {
    throw new Error("Unable to start a BE-020 integration-test game.");
  }

  const creationRepository = new SupabaseCreateIdeaRepository(serviceClient);
  const ideaIds: string[] = [];
  for (let index = 0; index < ideaCount; index += 1) {
    const created = await creationRepository.commitCreateIdea({
      actorUserId: context.actorUserId,
      runId,
      expectedVersion: index,
      title: createIdeaTitle(`BE-020 idea ${index + 1}`),
      description: null,
      evaluation: completedEvaluation,
    });
    ideaIds.push(created.ideaId);
  }

  return { context, runId, ideaIds };
}

async function addCurrentActivityUnavailableCondition(
  runId: string,
): Promise<void> {
  const run = await serviceClient
    .from("game_runs")
    .select("rule_set_id")
    .eq("id", runId)
    .single();
  if (!run.data) {
    throw new Error("BE-020 fixture run was not found.");
  }
  const healthRule = await serviceClient
    .from("health_risk_rules")
    .select("id")
    .eq("rule_set_id", run.data.rule_set_id)
    .limit(1)
    .single();
  if (!healthRule.data) {
    throw new Error("BE-020 fixture health rule was not found.");
  }

  const stateUpdate = await serviceClient
    .from("run_state")
    .update({ current_week: 2 })
    .eq("run_id", runId);
  if (stateUpdate.error) {
    throw new Error("Unable to advance a BE-020 fixture to its unavailable week.");
  }

  const { error } = await serviceClient.from("run_conditions").insert({
    run_id: runId,
    health_risk_rule_id: healthRule.data.id,
    started_week: 1,
    duration_weeks: 1,
    unavailable_from_week: 2,
    unavailable_through_week: 2,
  });
  if (error) {
    throw new Error("Unable to add a BE-020 activity-unavailable fixture.");
  }
}
