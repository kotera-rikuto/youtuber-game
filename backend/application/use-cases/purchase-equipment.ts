import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  EQUIPMENT_LEVELS,
  EQUIPMENT_TYPES,
  type EquipmentLevel,
  type EquipmentType,
} from "@/backend/domain/game/equipment";
import {
  PurchaseEquipmentCommitError,
  type EquipmentPurchaseRepository,
  type PurchaseEquipmentReceipt,
} from "@/backend/application/ports/equipment-purchase-repository";

export type PurchaseEquipmentInput = {
  runId: string;
  equipmentType: EquipmentType;
  level: EquipmentLevel;
  expectedVersion: number;
};

export type PurchaseEquipmentResult = PurchaseEquipmentReceipt;
export type PurchaseEquipmentErrorCode =
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

export class PurchaseEquipmentError extends Error {
  constructor(readonly code: PurchaseEquipmentErrorCode) {
    super("機材を購入できませんでした。");
    this.name = "PurchaseEquipmentError";
  }
}

export type PurchaseEquipmentDependencies = {
  equipmentPurchases: EquipmentPurchaseRepository;
};

const equipmentTypeValues: ReadonlySet<unknown> = new Set(EQUIPMENT_TYPES);
const equipmentLevelValues: ReadonlySet<unknown> = new Set(EQUIPMENT_LEVELS);
const POSTGRES_INTEGER_MAX = 2_147_483_647;

export async function purchaseEquipment(
  context: UseCaseContext,
  input: PurchaseEquipmentInput,
  dependencies: PurchaseEquipmentDependencies,
): Promise<PurchaseEquipmentResult> {
  if (
    typeof input !== "object" ||
    input === null ||
    typeof input.runId !== "string" ||
    input.runId.length === 0 ||
    !equipmentTypeValues.has(input.equipmentType)
  ) {
    throw new PurchaseEquipmentError("INVALID_EQUIPMENT_TYPE");
  }

  if (!equipmentLevelValues.has(input.level)) {
    throw new PurchaseEquipmentError("INVALID_EQUIPMENT_LEVEL");
  }

  if (
    !Number.isSafeInteger(input.expectedVersion) ||
    input.expectedVersion < 0 ||
    input.expectedVersion > POSTGRES_INTEGER_MAX
  ) {
    throw new PurchaseEquipmentError("STALE_STATE");
  }

  try {
    return await dependencies.equipmentPurchases.purchaseEquipment({
      actorUserId: context.actorUserId,
      runId: input.runId,
      equipmentType: input.equipmentType,
      level: input.level,
      expectedVersion: input.expectedVersion,
    });
  } catch (error) {
    if (error instanceof PurchaseEquipmentCommitError) {
      throw new PurchaseEquipmentError(error.code);
    }
    throw error;
  }
}