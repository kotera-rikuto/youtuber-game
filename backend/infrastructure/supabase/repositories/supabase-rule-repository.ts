import "server-only";

import { RepositoryError } from "@/backend/application/ports/repository-error";
import type { RuleRepository } from "@/backend/application/ports/rule-repository";
import type {
  ChannelRule,
  PostingFrequencyRule,
  PublishedRuleSet,
  SpecialtyRule,
} from "@/backend/domain/game/rules";
import {
  mapChannelRule,
  mapPostingFrequencyRule,
  mapPublishedRuleSet,
  mapSpecialtyRule,
} from "@/backend/infrastructure/supabase/mappers/rule-mapper";
import {
  type DatabaseClient,
  mapRepositoryData,
} from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseRuleRepository implements RuleRepository {
  constructor(private readonly client: DatabaseClient) {}

  async findActiveRuleSet(): Promise<PublishedRuleSet | null> {
    const operation = "rule.findActiveRuleSet";
    const { data, error } = await this.client
      .from("rule_sets")
      .select("id,version,status,published_at,created_at")
      .eq("status", "active")
      .not("published_at", "is", null)
      .maybeSingle();

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return data
      ? mapRepositoryData(operation, () => mapPublishedRuleSet(data))
      : null;
  }

  async findPublishedRuleSetById(
    ruleSetId: string,
  ): Promise<PublishedRuleSet | null> {
    const operation = "rule.findPublishedRuleSetById";
    const { data, error } = await this.client
      .from("rule_sets")
      .select("id,version,status,published_at,created_at")
      .eq("id", ruleSetId)
      .in("status", ["active", "retired"])
      .not("published_at", "is", null)
      .maybeSingle();

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return data
      ? mapRepositoryData(operation, () => mapPublishedRuleSet(data))
      : null;
  }

  async listChannelRules(ruleSetId: string): Promise<readonly ChannelRule[]> {
    const operation = "rule.listChannelRules";
    if (!(await this.findPublishedRuleSetById(ruleSetId))) {
      return [];
    }

    const { data, error } = await this.client
      .from("channel_rules")
      .select(
        "id,rule_set_id,channel_type_code,view_multiplier,weekly_flame_probability",
      )
      .eq("rule_set_id", ruleSetId)
      .order("channel_type_code", { ascending: true });

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () => data.map(mapChannelRule));
  }

  async listSpecialties(ruleSetId: string): Promise<readonly SpecialtyRule[]> {
    const operation = "rule.listSpecialties";
    if (!(await this.findPublishedRuleSetById(ruleSetId))) {
      return [];
    }

    const { data, error } = await this.client
      .from("rule_set_specialties")
      .select("rule_set_id,specialty_code")
      .eq("rule_set_id", ruleSetId)
      .order("specialty_code", { ascending: true });

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () => data.map(mapSpecialtyRule));
  }

  async listPostingFrequencies(
    ruleSetId: string,
  ): Promise<readonly PostingFrequencyRule[]> {
    const operation = "rule.listPostingFrequencies";
    if (!(await this.findPublishedRuleSetById(ruleSetId))) {
      return [];
    }

    const { data, error } = await this.client
      .from("posting_frequency_rules")
      .select(
        "id,rule_set_id,videos_per_week,view_multiplier,energy_cost,ability_points_awarded",
      )
      .eq("rule_set_id", ruleSetId)
      .order("videos_per_week", { ascending: true });

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () =>
      data.map(mapPostingFrequencyRule),
    );
  }
}
