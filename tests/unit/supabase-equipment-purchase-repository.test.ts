import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { PurchaseEquipmentCommand } from "@/backend/application/ports/equipment-purchase-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { SupabaseEquipmentPurchaseRepository } from "@/backend/infrastructure/supabase/repositories/supabase-equipment-purchase-repository";

vi.mock("server-only", () => ({}));

const command: PurchaseEquipmentCommand = {
  actorUserId: "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"],
  runId: "00000000-0000-4000-8000-000000000002",
  equipmentType: "camera",
  level: "beginner",
  expectedVersion: 4,
};

describe("SupabaseEquipmentPurchaseRepository", () => {
  it("calls the server-only RPC and maps its receipt", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        equipmentType: "camera",
        previousLevel: "none",
        purchasedLevel: "beginner",
        pricePaid: 30_000,
        cashAfter: 70_000,
        purchasedWeek: 1,
        nextStateVersion: 5,
      },
      error: null,
    });
    const repository = new SupabaseEquipmentPurchaseRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.purchaseEquipment(command)).resolves.toEqual({
      equipmentType: "camera",
      previousLevel: "none",
      purchasedLevel: "beginner",
      pricePaid: 30_000,
      cashAfter: 70_000,
      purchasedWeek: 1,
      nextStateVersion: 5,
    });
    expect(rpc).toHaveBeenCalledWith("purchase_equipment", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_equipment_type: command.equipmentType,
      p_level: command.level,
      p_expected_version: command.expectedVersion,
    });
  });

  it.each([
    ["PURCHASE_EQUIPMENT_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
    ["PURCHASE_EQUIPMENT_FORBIDDEN", "FORBIDDEN"],
    ["PURCHASE_EQUIPMENT_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
    ["PURCHASE_EQUIPMENT_ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
    ["PURCHASE_EQUIPMENT_STALE_STATE", "STALE_STATE"],
    ["PURCHASE_EQUIPMENT_INVALID_EQUIPMENT_TYPE", "INVALID_EQUIPMENT_TYPE"],
    ["PURCHASE_EQUIPMENT_INVALID_EQUIPMENT_LEVEL", "INVALID_EQUIPMENT_LEVEL"],
    ["PURCHASE_EQUIPMENT_EQUIPMENT_RULE_UNAVAILABLE", "EQUIPMENT_RULE_UNAVAILABLE"],
    ["PURCHASE_EQUIPMENT_SAME_OR_LOWER_TIER", "SAME_OR_LOWER_TIER"],
    ["PURCHASE_EQUIPMENT_INSUFFICIENT_CASH", "INSUFFICIENT_CASH"],
  ] as const)("maps %s", async (message, code) => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: "P0001", message },
    });
    const repository = new SupabaseEquipmentPurchaseRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.purchaseEquipment(command)).rejects.toMatchObject({ code });
  });

  it("maps unknown errors and malformed receipts to COMMIT_FAILED", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { equipmentType: "camera" },
      error: null,
    });
    const repository = new SupabaseEquipmentPurchaseRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.purchaseEquipment(command)).rejects.toMatchObject({
      code: "COMMIT_FAILED",
    });
  });
});