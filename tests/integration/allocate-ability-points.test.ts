import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import { allocateAbilityPoints } from "@/backend/application/use-cases/allocate-ability-points";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabaseAbilityAllocationRepository } from "@/backend/infrastructure/supabase/repositories/supabase-ability-allocation-repository";
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

describe("allocateAbilityPoints integration", () => {
  it("allocates all six abilities, saves history, consumes the grant, and only advances the version", async () => {
    const fixture = await startGameFixture("all-six");
    const grantId = await insertGrant(fixture.runId, { amount: 21 });
    const repository = new SupabaseAbilityAllocationRepository(serviceClient);

    await expect(
      allocateAbilityPoints(
        fixture.context,
        {
          runId: fixture.runId,
          planning: 1,
          talking: 2,
          expertise: 3,
          editing: 4,
          visual: 5,
          filming: 6,
          expectedVersion: 0,
        },
        { abilityAllocations: repository },
      ),
    ).resolves.toEqual({ nextStateVersion: 1 });

    const [abilities, allocations, grant, state, actions] = await Promise.all([
      serviceClient
        .from("run_abilities")
        .select("ability_code,value")
        .eq("run_id", fixture.runId)
        .order("ability_code"),
      serviceClient
        .from("ability_allocations")
        .select("ability_code,points,allocated_week,grant_id")
        .eq("grant_id", grantId)
        .order("ability_code"),
      serviceClient
        .from("ability_point_grants")
        .select("status")
        .eq("id", grantId)
        .single(),
      serviceClient
        .from("run_state")
        .select("state_version,energy,cash,current_week")
        .eq("run_id", fixture.runId)
        .single(),
      serviceClient
        .from("weekly_actions")
        .select("id", { count: "exact", head: true })
        .eq("run_id", fixture.runId),
    ]);

    expect(abilities.error).toBeNull();
    expect(Object.fromEntries(abilities.data!.map(({ ability_code, value }) => [ability_code, value]))).toEqual({
      editing: 14,
      expertise: 13,
      filming: 16,
      planning: 11,
      talking: 12,
      visual: 15,
    });
    expect(allocations.error).toBeNull();
    expect(allocations.data).toHaveLength(6);
    expect(allocations.data?.reduce((sum, row) => sum + row.points, 0)).toBe(21);
    expect(allocations.data?.every((row) => row.allocated_week === 1)).toBe(true);
    expect(grant.data).toEqual({ status: "consumed" });
    expect(state.data).toEqual({
      state_version: 1,
      energy: 100,
      cash: 100_000,
      current_week: 1,
    });
    expect(actions.count).toBe(0);
  });

  it("consumes grants in deterministic order and leaves a partial grant available", async () => {
    const fixture = await startGameFixture("multiple-grants");
    await serviceClient
      .from("run_state")
      .update({ current_week: 2 })
      .eq("run_id", fixture.runId)
      .throwOnError();
    const firstGrantId = await insertGrant(fixture.runId, {
      amount: 3,
      earnedWeek: 1,
      availableFromWeek: 1,
    });
    const secondGrantId = await insertGrant(fixture.runId, {
      amount: 5,
      earnedWeek: 2,
      availableFromWeek: 2,
    });
    const repository = new SupabaseAbilityAllocationRepository(serviceClient);

    await allocateAbilityPoints(
      fixture.context,
      {
        runId: fixture.runId,
        planning: 4,
        talking: 1,
        expertise: 0,
        editing: 0,
        visual: 0,
        filming: 0,
        expectedVersion: 0,
      },
      { abilityAllocations: repository },
    );

    const { data: grants } = await serviceClient
      .from("ability_point_grants")
      .select("id,status")
      .in("id", [firstGrantId, secondGrantId]);
    const { data: allocations } = await serviceClient
      .from("ability_allocations")
      .select("grant_id,ability_code,points")
      .in("grant_id", [firstGrantId, secondGrantId]);

    expect(grants).toEqual(
      expect.arrayContaining([
        { id: firstGrantId, status: "consumed" },
        { id: secondGrantId, status: "available" },
      ]),
    );
    expect(allocations).toHaveLength(3);
    expect(allocations).toEqual(
      expect.arrayContaining([
        { grant_id: firstGrantId, ability_code: "planning", points: 3 },
        { grant_id: secondGrantId, ability_code: "planning", points: 1 },
        { grant_id: secondGrantId, ability_code: "talking", points: 1 },
      ]),
    );
  });

  it("allows an ability to reach exactly 100", async () => {
    const fixture = await startGameFixture("exact-limit");
    await serviceClient
      .from("run_abilities")
      .update({ value: 98 })
      .eq("run_id", fixture.runId)
      .eq("ability_code", "planning")
      .throwOnError();
    await insertGrant(fixture.runId, { amount: 2 });

    await allocateAbilityPoints(
      fixture.context,
      zeroInput(fixture.runId, { planning: 2 }),
      { abilityAllocations: new SupabaseAbilityAllocationRepository(serviceClient) },
    );

    const { data } = await serviceClient
      .from("run_abilities")
      .select("value")
      .eq("run_id", fixture.runId)
      .eq("ability_code", "planning")
      .single();
    expect(data?.value).toBe(100);
  });

  it.each([
    ["INSUFFICIENT_ABILITY_POINTS", { grantAmount: 2, planningValue: 10, planning: 3 }],
    ["ABILITY_LIMIT_EXCEEDED", { grantAmount: 3, planningValue: 99, planning: 2 }],
  ] as const)("rolls back every table on %s", async (code, setup) => {
    const fixture = await startGameFixture(`rollback-${code}`);
    const grantId = await insertGrant(fixture.runId, { amount: setup.grantAmount });
    await serviceClient
      .from("run_abilities")
      .update({ value: setup.planningValue })
      .eq("run_id", fixture.runId)
      .eq("ability_code", "planning")
      .throwOnError();

    await expect(
      allocateAbilityPoints(
        fixture.context,
        zeroInput(fixture.runId, { planning: setup.planning, talking: 1 }),
        { abilityAllocations: new SupabaseAbilityAllocationRepository(serviceClient) },
      ),
    ).rejects.toMatchObject({ code });

    const [abilities, allocationCount, grant, state] = await Promise.all([
      serviceClient
        .from("run_abilities")
        .select("ability_code,value")
        .eq("run_id", fixture.runId)
        .in("ability_code", ["planning", "talking"]),
      serviceClient
        .from("ability_allocations")
        .select("id", { count: "exact", head: true })
        .eq("grant_id", grantId),
      serviceClient.from("ability_point_grants").select("status").eq("id", grantId).single(),
      serviceClient.from("run_state").select("state_version").eq("run_id", fixture.runId).single(),
    ]);
    expect(abilities.data).toEqual(
      expect.arrayContaining([
        { ability_code: "planning", value: setup.planningValue },
        { ability_code: "talking", value: 10 },
      ]),
    );
    expect(allocationCount.count).toBe(0);
    expect(grant.data?.status).toBe("available");
    expect(state.data?.state_version).toBe(0);
  });

  it("rejects activity-unavailable, forbidden, and stale requests", async () => {
    const fixture = await startGameFixture("guards");
    const other = await startGameFixture("other-owner");
    await insertGrant(fixture.runId, { amount: 3 });
    const { data: run } = await serviceClient
      .from("game_runs")
      .select("rule_set_id")
      .eq("id", fixture.runId)
      .single();
    const { data: healthRule } = await serviceClient
      .from("health_risk_rules")
      .select("id")
      .eq("rule_set_id", run!.rule_set_id)
      .limit(1)
      .single();
    await serviceClient
      .from("run_state")
      .update({ current_week: 2 })
      .eq("run_id", fixture.runId)
      .throwOnError();
    await serviceClient
      .from("run_conditions")
      .insert({
        run_id: fixture.runId,
        health_risk_rule_id: healthRule!.id,
        started_week: 1,
        duration_weeks: 1,
        unavailable_from_week: 2,
        unavailable_through_week: 2,
      })
      .throwOnError();
    const repository = new SupabaseAbilityAllocationRepository(serviceClient);

    await expect(
      allocateAbilityPoints(fixture.context, zeroInput(fixture.runId, { planning: 1 }), {
        abilityAllocations: repository,
      }),
    ).rejects.toMatchObject({ code: "ACTIVITY_UNAVAILABLE" });
    await expect(
      allocateAbilityPoints(other.context, zeroInput(fixture.runId, { planning: 1 }), {
        abilityAllocations: repository,
      }),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
    await expect(
      allocateAbilityPoints(fixture.context, {
        ...zeroInput(fixture.runId, { planning: 1 }),
        expectedVersion: 99,
      }, { abilityAllocations: repository }),
    ).rejects.toMatchObject({ code: "STALE_STATE" });
  });

  it("allows only one concurrent request to spend the same points", async () => {
    const fixture = await startGameFixture("concurrent");
    const grantId = await insertGrant(fixture.runId, { amount: 5 });
    const repository = new SupabaseAbilityAllocationRepository(serviceClient);

    const attempts = await Promise.allSettled([
      allocateAbilityPoints(fixture.context, zeroInput(fixture.runId, { planning: 5 }), {
        abilityAllocations: repository,
      }),
      allocateAbilityPoints(fixture.context, zeroInput(fixture.runId, { talking: 5 }), {
        abilityAllocations: repository,
      }),
    ]);

    expect(attempts.filter((attempt) => attempt.status === "fulfilled")).toHaveLength(1);
    expect(attempts.find((attempt) => attempt.status === "rejected")).toMatchObject({
      reason: { code: "STALE_STATE" },
    });
    const [allocationCount, allocationSum, state] = await Promise.all([
      serviceClient.from("ability_allocations").select("id", { count: "exact", head: true }).eq("grant_id", grantId),
      serviceClient.from("ability_allocations").select("points").eq("grant_id", grantId),
      serviceClient.from("run_state").select("state_version").eq("run_id", fixture.runId).single(),
    ]);
    expect(allocationCount.count).toBe(1);
    expect(allocationSum.data?.reduce((sum, row) => sum + row.points, 0)).toBe(5);
    expect(state.data?.state_version).toBe(1);
  });

  it("keeps saved allocation history immutable", async () => {
    const fixture = await startGameFixture("immutable");
    const grantId = await insertGrant(fixture.runId, { amount: 1 });
    await allocateAbilityPoints(fixture.context, zeroInput(fixture.runId, { planning: 1 }), {
      abilityAllocations: new SupabaseAbilityAllocationRepository(serviceClient),
    });
    const { data: allocation } = await serviceClient
      .from("ability_allocations")
      .select("id")
      .eq("grant_id", grantId)
      .single();

    const updateResult = await serviceClient
      .from("ability_allocations")
      .update({ points: 2 })
      .eq("id", allocation!.id);
    const deleteResult = await serviceClient
      .from("ability_allocations")
      .delete()
      .eq("id", allocation!.id);
    expect(updateResult.error?.code).toBe("23514");
    expect(deleteResult.error?.code).toBe("23514");
  });
});

async function startGameFixture(label: string): Promise<{
  context: UseCaseContext;
  runId: string;
}> {
  const email = `be022-${label}-${crypto.randomUUID()}@example.test`;
  const { data: userResult, error: userError } =
    await serviceClient.auth.admin.createUser({
      email,
      password: "BE-022-local-password",
      email_confirm: true,
    });
  if (userError) {
    throw new Error("Unable to create a BE-022 integration-test user.");
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
      p_channel_name: `BE-022 ${label}`,
      p_posting_style: "mainstream",
    },
  );
  if (startError || !runId) {
    throw new Error("Unable to start a BE-022 integration-test game.");
  }
  return { context, runId };
}

async function insertGrant(
  runId: string,
  input: {
    amount: number;
    earnedWeek?: number;
    availableFromWeek?: number;
  },
): Promise<string> {
  const { data, error } = await serviceClient
    .from("ability_point_grants")
    .insert({
      run_id: runId,
      earned_week: input.earnedWeek ?? 1,
      available_from_week: input.availableFromWeek ?? 1,
      amount: input.amount,
      status: "available",
    })
    .select("id")
    .single();
  if (error) {
    throw new Error(`Unable to add a BE-022 grant: ${error.message}`);
  }
  return data.id;
}

function zeroInput(
  runId: string,
  allocations: Partial<{
    planning: number;
    talking: number;
    expertise: number;
    editing: number;
    visual: number;
    filming: number;
  }> = {},
) {
  return {
    runId,
    planning: 0,
    talking: 0,
    expertise: 0,
    editing: 0,
    visual: 0,
    filming: 0,
    expectedVersion: 0,
    ...allocations,
  };
}
