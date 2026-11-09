import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type {
  EquipmentLevel,
  EquipmentType,
} from "@/backend/domain/game/equipment";

export type PurchaseEquipmentCommand = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
  equipmentType: EquipmentType;
  level: EquipmentLevel;
  expectedVersion: number;
};

export type PurchaseEquipmentReceipt = {
  equipmentType: EquipmentType;
  previousLevel: "none" | EquipmentLevel;
  purchasedLevel: EquipmentLevel;
  pricePaid: number;
  cashAfter: number;
  purchasedWeek: number;
  nextStateVersion: number;
};

export type PurchaseEquipmentCommitErrorCode =
  | "RUN_NOT_FOUND"
  | "FORBIDDEN"
  | "RUN_NOT_PLAYABLE"
  | "ACTIVITY_UNAVAILABLE"
  | "STALE_STATE"
  | "INVALID_EQUIPMENT_TYPE"
  | "INVALID_EQUIPMENT_LEVEL"
  | "EQUIPMENT_RULE_UNAVAILABLE"
  | "SAME_OR_LOWER_TIER"
  | "INSUFFICIENT_CASH"
  | "COMMIT_FAILED";

export class PurchaseEquipmentCommitError extends Error {
  constructor(readonly code: PurchaseEquipmentCommitErrorCode) {
    super("The equipment purchase could not be completed.");
    this.name = "PurchaseEquipmentCommitError";
  }
}

export interface EquipmentPurchaseRepository {
  purchaseEquipment(
    command: PurchaseEquipmentCommand,
  ): Promise<PurchaseEquipmentReceipt>;
}