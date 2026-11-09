import "server-only";

import type { PurchaseEquipmentDependencies } from "@/backend/application/use-cases/purchase-equipment";
import { SupabaseEquipmentPurchaseRepository } from "@/backend/infrastructure/supabase/repositories/supabase-equipment-purchase-repository";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

export function createPurchaseEquipmentDependencies(): PurchaseEquipmentDependencies {
  return {
    equipmentPurchases: new SupabaseEquipmentPurchaseRepository(
      createTrustedSupabaseClient(),
    ),
  };
}