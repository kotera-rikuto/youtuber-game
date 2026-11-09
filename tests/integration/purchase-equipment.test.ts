import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { requireUseCaseContext, type UseCaseContext } from "@/backend/application/auth/authentication";
import { purchaseEquipment } from "@/backend/application/use-cases/purchase-equipment";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabaseEquipmentPurchaseRepository } from "@/backend/infrastructure/supabase/repositories/supabase-equipment-purchase-repository";
import { validateLocalIntegrationEnvironment } from "@/scripts/repository-integration-environment.js";

vi.mock("server-only", () => ({}));

const INITIAL_CASH = 100_000;

const environment = validateLocalIntegrationEnvironment({
  url: process.env.SUPABASE_INTEGRATION_URL,
  publishableKey: process.env.SUPABASE_INTEGRATION_PUBLISHABLE_KEY,
  secretKey: process.env.SUPABASE_INTEGRATION_SECRET_KEY,
  databaseUrl: process.env.SUPABASE_INTEGRATION_DB_URL,
});
const clientOptions = {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
} as const;
let serviceClient: SupabaseClient<Database>;

beforeAll(() => {
  serviceClient = createClient<Database>(environment.url, environment.secretKey, clientOptions);
});

describe("purchaseEquipment integration", () => {
  it.each([
    ["beginner", 30_000, INITIAL_CASH],
    ["intermediate", 150_000, 500_000],
    ["advanced", 500_000, 1_000_000],
  ] as const)("purchases camera from none directly to %s using the DB price", async (level, price, cashBefore) => {
    const fixture = await startGameFixture(`none-${level}`);
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    await setRunCash(fixture.runId, cashBefore);

    await expect(purchaseEquipment(fixture.context, {
      runId: fixture.runId, equipmentType: "camera", level, expectedVersion: 0,
    }, { equipmentPurchases: repository })).resolves.toMatchObject({
      equipmentType: "camera", previousLevel: "none", purchasedLevel: level,
      pricePaid: price, cashAfter: cashBefore - price, purchasedWeek: 1, nextStateVersion: 1,
    });
  });

  it("supports every upward transition and never charges a difference", async () => {
    const fixture = await startGameFixture("upgrades");
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    await setRunCash(fixture.runId, 135_000);
    const purchase = async (level: "beginner" | "intermediate" | "advanced", expectedVersion: number) =>
      purchaseEquipment(fixture.context, {
        runId: fixture.runId, equipmentType: "microphone", level, expectedVersion,
      }, { equipmentPurchases: repository });

    await expect(purchase("beginner", 0)).resolves.toMatchObject({ pricePaid: 5_000, cashAfter: 130_000 });
    await expect(purchase("intermediate", 1)).resolves.toMatchObject({ pricePaid: 30_000, cashAfter: 100_000 });
    await expect(purchase("advanced", 2)).resolves.toMatchObject({ pricePaid: 100_000, cashAfter: 0 });
  });

  it.each(["beginner", "intermediate"] as const)("rejects same or lower tier from advanced: %s", async (level) => {
    const fixture = await startGameFixture(`reject-${level}`);
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    await setRunCash(fixture.runId, 500_000);
    await purchaseEquipment(fixture.context, {
      runId: fixture.runId, equipmentType: "editing_pc", level: "advanced", expectedVersion: 0,
    }, { equipmentPurchases: repository });

    await expect(purchaseEquipment(fixture.context, {
      runId: fixture.runId, equipmentType: "editing_pc", level, expectedVersion: 1,
    }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "SAME_OR_LOWER_TIER" });
  });

  it("rejects none, unsupported values, insufficient cash, forbidden, unavailable, and stale requests", async () => {
    const fixture = await startGameFixture("guards");
    const other = await startGameFixture("other");
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    const base = { runId: fixture.runId, equipmentType: "camera" as const, expectedVersion: 0 };

    await expect(purchaseEquipment(fixture.context, { ...base, level: "none" as never }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "INVALID_EQUIPMENT_LEVEL" });
    await expect(purchaseEquipment(fixture.context, { ...base, equipmentType: "phone" as never, level: "beginner" }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "INVALID_EQUIPMENT_TYPE" });
    await expect(purchaseEquipment(other.context, { ...base, level: "beginner" }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "FORBIDDEN" });

    await serviceClient.from("run_state").update({ cash: 1 }).eq("run_id", fixture.runId).throwOnError();
    await expect(purchaseEquipment(fixture.context, { ...base, level: "beginner" }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "INSUFFICIENT_CASH" });

    const { data: run } = await serviceClient.from("game_runs").select("rule_set_id").eq("id", fixture.runId).single();
    const { data: healthRule } = await serviceClient.from("health_risk_rules").select("id").eq("rule_set_id", run!.rule_set_id).limit(1).single();
    await serviceClient.from("run_state").update({ cash: 100_000, current_week: 2 }).eq("run_id", fixture.runId).throwOnError();
    await serviceClient.from("run_conditions").insert({ run_id: fixture.runId, health_risk_rule_id: healthRule!.id, started_week: 1, duration_weeks: 1, unavailable_from_week: 2, unavailable_through_week: 2 }).throwOnError();
    await expect(purchaseEquipment(fixture.context, { ...base, level: "beginner" }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "ACTIVITY_UNAVAILABLE" });
    await expect(purchaseEquipment(fixture.context, { ...base, level: "beginner", expectedVersion: 99 }, { equipmentPurchases: repository })).rejects.toMatchObject({ code: "STALE_STATE" });
  });

  it("changes only cash, equipment, purchase history, and state version", async () => {
    const fixture = await startGameFixture("atomic");
    await serviceClient.from("weekly_actions").insert({ run_id: fixture.runId, week_number: 1, action_rule_id: "00000000-0000-4000-8100-000000001601" }).throwOnError();
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    await purchaseEquipment(fixture.context, { runId: fixture.runId, equipmentType: "camera", level: "beginner", expectedVersion: 0 }, { equipmentPurchases: repository });

    const [state, equipment, history] = await Promise.all([
      serviceClient.from("run_state").select("cash,energy,current_week,state_version").eq("run_id", fixture.runId).single(),
      serviceClient.from("run_equipment").select("equipment_type_code,acquired_week,equipment_tier_rule_id").eq("run_id", fixture.runId).single(),
      serviceClient.from("equipment_purchases").select("from_tier_rule_id,to_tier_rule_id,price_paid,purchased_week").eq("run_id", fixture.runId).single(),
    ]);
    expect(state.data).toMatchObject({ cash: 70_000, energy: 100, current_week: 1, state_version: 1 });
    expect(equipment.data).toMatchObject({ equipment_type_code: "camera", acquired_week: 1 });
    expect(history.data).toMatchObject({ from_tier_rule_id: null, price_paid: 30_000, purchased_week: 1 });
    expect(history.data?.to_tier_rule_id).toBe(equipment.data?.equipment_tier_rule_id);
  });

  it("allows only one concurrent purchase with the same version", async () => {
    const fixture = await startGameFixture("concurrent");
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    const attempts = await Promise.allSettled([
      purchaseEquipment(fixture.context, { runId: fixture.runId, equipmentType: "camera", level: "beginner", expectedVersion: 0 }, { equipmentPurchases: repository }),
      purchaseEquipment(fixture.context, { runId: fixture.runId, equipmentType: "microphone", level: "beginner", expectedVersion: 0 }, { equipmentPurchases: repository }),
    ]);
    expect(attempts.filter(({ status }) => status === "fulfilled")).toHaveLength(1);
    expect(attempts.find(({ status }) => status === "rejected")).toMatchObject({ reason: { code: "STALE_STATE" } });
  });

  it("keeps purchase history immutable", async () => {
    const fixture = await startGameFixture("immutable");
    const repository = new SupabaseEquipmentPurchaseRepository(serviceClient);
    await purchaseEquipment(fixture.context, { runId: fixture.runId, equipmentType: "camera", level: "beginner", expectedVersion: 0 }, { equipmentPurchases: repository });
    const { data: history } = await serviceClient.from("equipment_purchases").select("id").eq("run_id", fixture.runId).single();
    const update = await serviceClient.from("equipment_purchases").update({ price_paid: 1 }).eq("id", history!.id);
    const deletion = await serviceClient.from("equipment_purchases").delete().eq("id", history!.id);
    expect(update.error?.code).toBe("23514");
    expect(deletion.error?.code).toBe("23514");
  });
});

async function startGameFixture(label: string): Promise<{ context: UseCaseContext; runId: string }> {
  const { data: user, error: userError } = await serviceClient.auth.admin.createUser({
    email: `be023-${label}-${crypto.randomUUID()}@example.test`, password: "BE-023-local-password", email_confirm: true,
  });
  if (userError || !user.user) throw new Error("Unable to create a BE-023 integration user.");
  const context = await requireUseCaseContext({ getVerifiedUser: async () => ({ status: "authenticated", userId: user.user.id }) });
  const { data: runId, error } = await serviceClient.rpc("commit_start_game", {
    p_actor_user_id: context.actorUserId, p_channel_name: `BE-023 ${label}`, p_posting_style: "mainstream",
  });
  if (error || !runId) throw new Error(`Unable to start a BE-023 fixture: ${error?.message ?? "no run"}`);
  return { context, runId };
}

async function setRunCash(runId: string, cash: number): Promise<void> {
  await serviceClient
    .from("run_state")
    .update({ cash })
    .eq("run_id", runId)
    .throwOnError();
}
