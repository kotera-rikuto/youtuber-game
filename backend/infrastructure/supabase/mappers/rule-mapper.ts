import "server-only";

import type {
  ChannelRule,
  PostingFrequencyRule,
  PublishedRuleSet,
  SpecialtyRule,
} from "@/backend/domain/game/rules";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import {
  parseDate,
  requireFiniteNumber,
  requireNonnegativeInteger,
  requirePositiveInteger,
  requireString,
} from "@/backend/infrastructure/supabase/mappers/validation";

type RuleSetRow = Database["public"]["Tables"]["rule_sets"]["Row"];
type ChannelRuleRow =
  Database["public"]["Tables"]["channel_rules"]["Row"];
type SpecialtyRuleRow =
  Database["public"]["Tables"]["rule_set_specialties"]["Row"];
type PostingFrequencyRuleRow =
  Database["public"]["Tables"]["posting_frequency_rules"]["Row"];

export function mapPublishedRuleSet(row: RuleSetRow): PublishedRuleSet {
  if (
    (row.status !== "active" && row.status !== "retired") ||
    row.published_at === null
  ) {
    throw new DataIntegrityError("Rule set must be published.");
  }

  return {
    id: requireString(row.id, "id"),
    version: requireString(row.version, "version"),
    status: row.status,
    publishedAt: parseDate(row.published_at, "published_at"),
  };
}

export function mapChannelRule(row: ChannelRuleRow): ChannelRule {
  return {
    id: requireString(row.id, "id"),
    ruleSetId: requireString(row.rule_set_id, "rule_set_id"),
    channelTypeCode: requireString(
      row.channel_type_code,
      "channel_type_code",
    ),
    viewMultiplier: requireFiniteNumber(row.view_multiplier, "view_multiplier"),
    weeklyFlameProbability: requireFiniteNumber(
      row.weekly_flame_probability,
      "weekly_flame_probability",
    ),
  };
}

export function mapSpecialtyRule(row: SpecialtyRuleRow): SpecialtyRule {
  return {
    ruleSetId: requireString(row.rule_set_id, "rule_set_id"),
    specialtyCode: requireString(row.specialty_code, "specialty_code"),
  };
}

export function mapPostingFrequencyRule(
  row: PostingFrequencyRuleRow,
): PostingFrequencyRule {
  return {
    id: requireString(row.id, "id"),
    ruleSetId: requireString(row.rule_set_id, "rule_set_id"),
    videosPerWeek: requirePositiveInteger(
      row.videos_per_week,
      "videos_per_week",
    ),
    viewMultiplier: requireFiniteNumber(row.view_multiplier, "view_multiplier"),
    energyCost: requireNonnegativeInteger(row.energy_cost, "energy_cost"),
    abilityPointsAwarded: requireNonnegativeInteger(
      row.ability_points_awarded,
      "ability_points_awarded",
    ),
  };
}
