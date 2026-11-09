export const EQUIPMENT_TYPES = ["camera", "microphone", "editing_pc"] as const;
export type EquipmentType = (typeof EQUIPMENT_TYPES)[number];

export const EQUIPMENT_LEVELS = [
  "beginner",
  "intermediate",
  "advanced",
] as const;
export type EquipmentLevel = (typeof EQUIPMENT_LEVELS)[number];

export const EQUIPMENT_TIER_ORDER = {
  none: 0,
  beginner: 1,
  intermediate: 2,
  advanced: 3,
} as const;

export type EquipmentTier = keyof typeof EQUIPMENT_TIER_ORDER;