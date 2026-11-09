import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  PurchaseEquipmentCommitError,
  type EquipmentPurchaseRepository,
} from "@/backend/application/ports/equipment-purchase-repository";
import {
  purchaseEquipment,
  type PurchaseEquipmentInput,
} from "@/backend/application/use-cases/purchase-equipment";

const context: UseCaseContext = {
  actorUserId: "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"],
};
const input: PurchaseEquipmentInput = {
  runId: "00000000-0000-4000-8000-000000000002",
  equipmentType: "camera",
  level: "beginner",
  expectedVersion: 4,
};

describe("purchaseEquipment", () => {
  it("passes only client-controlled selectors and verified actor to the repository", async () => {
    const purchase = vi.fn().mockResolvedValue({
      equipmentType: "camera",
      previousLevel: "none",
      purchasedLevel: "beginner",
      pricePaid: 30_000,
      cashAfter: 70_000,
      purchasedWeek: 1,
      nextStateVersion: 5,
    });
    const equipmentPurchases = { purchaseEquipment: purchase } satisfies EquipmentPurchaseRepository;

    await expect(purchaseEquipment(context, input, { equipmentPurchases })).resolves.toEqual(
      expect.objectContaining({ pricePaid: 30_000 }),
    );
    expect(purchase).toHaveBeenCalledWith({
      actorUserId: context.actorUserId,
      runId: input.runId,
      equipmentType: input.equipmentType,
      level: input.level,
      expectedVersion: input.expectedVersion,
    });
  });

  it.each([
    ["invalid type", { equipmentType: "phone" }, "INVALID_EQUIPMENT_TYPE"],
    ["none level", { level: "none" }, "INVALID_EQUIPMENT_LEVEL"],
    ["invalid level", { level: "elite" }, "INVALID_EQUIPMENT_LEVEL"],
    ["negative version", { expectedVersion: -1 }, "STALE_STATE"],
  ] as const)("rejects %s before persistence", async (_label, override, code) => {
    const purchase = vi.fn();
    const equipmentPurchases = { purchaseEquipment: purchase } satisfies EquipmentPurchaseRepository;

    await expect(
      purchaseEquipment(context, { ...input, ...override } as PurchaseEquipmentInput, {
        equipmentPurchases,
      }),
    ).rejects.toMatchObject({ code });
    expect(purchase).not.toHaveBeenCalled();
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_PLAYABLE",
    "ACTIVITY_UNAVAILABLE",
    "STALE_STATE",
    "EQUIPMENT_RULE_UNAVAILABLE",
    "SAME_OR_LOWER_TIER",
    "INSUFFICIENT_CASH",
    "COMMIT_FAILED",
  ] as const)("preserves repository error %s", async (code) => {
    const equipmentPurchases: EquipmentPurchaseRepository = {
      purchaseEquipment: vi.fn().mockRejectedValue(
        new PurchaseEquipmentCommitError(code),
      ),
    };

    await expect(
      purchaseEquipment(context, input, { equipmentPurchases }),
    ).rejects.toMatchObject({ code });
  });
});