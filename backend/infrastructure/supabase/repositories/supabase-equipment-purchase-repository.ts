import "server-only";

import {
  PurchaseEquipmentCommitError,
  type EquipmentPurchaseRepository,
  type PurchaseEquipmentCommand,
  type PurchaseEquipmentReceipt,
} from "@/backend/application/ports/equipment-purchase-repository";
import {
  EQUIPMENT_LEVELS,
  EQUIPMENT_TYPES,
  type EquipmentLevel,
  type EquipmentType,
} from "@/backend/domain/game/equipment";
import type { Json } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseEquipmentPurchaseRepository
  implements EquipmentPurchaseRepository
{
  constructor(private readonly client: DatabaseClient) {}

  async purchaseEquipment(
    command: PurchaseEquipmentCommand,
  ): Promise<PurchaseEquipmentReceipt> {
    const { data, error } = await this.client.rpc("purchase_equipment", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_equipment_type: command.equipmentType,
      p_level: command.level,
      p_expected_version: command.expectedVersion,
    });

    if (error) {
      throw mapPurchaseEquipmentRpcError(error.message);
    }

    return mapReceipt(data);
  }
}

const purchaseEquipmentErrorCodes = new Map<
  string,
  PurchaseEquipmentCommitError["code"]
>([
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
]);

function mapPurchaseEquipmentRpcError(
  message: string,
): PurchaseEquipmentCommitError {
  return new PurchaseEquipmentCommitError(
    purchaseEquipmentErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}

function mapReceipt(data: Json): PurchaseEquipmentReceipt {
  if (
    !isJsonObject(data) ||
    !isEquipmentType(data.equipmentType) ||
    !isEquipmentTier(data.previousLevel) ||
    !isEquipmentLevel(data.purchasedLevel) ||
    !isNonnegativeInteger(data.pricePaid) ||
    !isNonnegativeInteger(data.cashAfter) ||
    !isPositiveInteger(data.purchasedWeek) ||
    !isPositiveInteger(data.nextStateVersion)
  ) {
    throw new PurchaseEquipmentCommitError("COMMIT_FAILED");
  }

  return {
    equipmentType: data.equipmentType,
    previousLevel: data.previousLevel,
    purchasedLevel: data.purchasedLevel,
    pricePaid: data.pricePaid,
    cashAfter: data.cashAfter,
    purchasedWeek: data.purchasedWeek,
    nextStateVersion: data.nextStateVersion,
  };
}

type JsonObject = { [key: string]: Json | undefined };

function isJsonObject(value: Json): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isEquipmentType(value: Json | undefined): value is EquipmentType {
  return typeof value === "string" && EQUIPMENT_TYPES.includes(value as EquipmentType);
}

function isEquipmentLevel(value: Json | undefined): value is EquipmentLevel {
  return typeof value === "string" && EQUIPMENT_LEVELS.includes(value as EquipmentLevel);
}

function isEquipmentTier(value: Json | undefined): value is "none" | EquipmentLevel {
  return value === "none" || isEquipmentLevel(value);
}

function isNonnegativeInteger(value: Json | undefined): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function isPositiveInteger(value: Json | undefined): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}