import "server-only";

import type { Database } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { createTrustedSupabaseClient } from "@/backend/infrastructure/supabase/trusted-client";

type ChannelTypeRow = Pick<
  Database["public"]["Tables"]["channel_types"]["Row"],
  "code" | "name" | "display_order"
>;
type SpecialtyRow = Pick<
  Database["public"]["Tables"]["specialty_categories"]["Row"],
  "code" | "name" | "display_order"
>;

export type GameStartOptionDTO = {
  code: string;
  name: string;
  displayOrder: number;
};

export type GameStartOptionsDTO = {
  postingStyles: readonly GameStartOptionDTO[];
  specialties: readonly GameStartOptionDTO[];
};

export interface GameStartOptionsSource {
  loadActiveOptions(): Promise<{
    postingStyles: readonly ChannelTypeRow[];
    specialties: readonly SpecialtyRow[];
  }>;
}

export async function getGameStartOptionsDTO(
  source: GameStartOptionsSource = new SupabaseGameStartOptionsSource(
    createTrustedSupabaseClient(),
  ),
): Promise<GameStartOptionsDTO> {
  const options = await source.loadActiveOptions();

  return {
    postingStyles: mapOptions(options.postingStyles),
    specialties: mapOptions(options.specialties),
  };
}

class SupabaseGameStartOptionsSource implements GameStartOptionsSource {
  constructor(private readonly client: DatabaseClient) {}

  async loadActiveOptions() {
    const { data: activeRuleSet, error: activeRuleSetError } = await this.client
      .from("rule_sets")
      .select("id")
      .eq("status", "active")
      .not("published_at", "is", null)
      .maybeSingle();

    if (activeRuleSetError || !activeRuleSet) {
      throw new Error("Active game-start rules are unavailable.");
    }

    const [channelRulesResponse, specialtyRulesResponse] = await Promise.all([
      this.client
        .from("channel_rules")
        .select("channel_type_code")
        .eq("rule_set_id", activeRuleSet.id),
      this.client
        .from("rule_set_specialties")
        .select("specialty_code")
        .eq("rule_set_id", activeRuleSet.id),
    ]);

    if (channelRulesResponse.error || specialtyRulesResponse.error) {
      throw new Error("Active game-start rules are unavailable.");
    }

    const postingStyleCodes = channelRulesResponse.data.map(
      (rule) => rule.channel_type_code,
    );
    const specialtyCodes = specialtyRulesResponse.data.map(
      (rule) => rule.specialty_code,
    );

    const [postingStylesResponse, specialtiesResponse] = await Promise.all([
      this.client
        .from("channel_types")
        .select("code,name,display_order")
        .in("code", postingStyleCodes)
        .order("display_order", { ascending: true }),
      this.client
        .from("specialty_categories")
        .select("code,name,display_order")
        .in("code", specialtyCodes)
        .order("display_order", { ascending: true }),
    ]);

    if (postingStylesResponse.error || specialtiesResponse.error) {
      throw new Error("Active game-start options are unavailable.");
    }

    return {
      postingStyles: postingStylesResponse.data,
      specialties: specialtiesResponse.data,
    };
  }
}

function mapOptions(
  rows: readonly (ChannelTypeRow | SpecialtyRow)[],
): GameStartOptionDTO[] {
  return [...rows]
    .sort((left, right) => left.display_order - right.display_order)
    .map((row) => ({
      code: row.code,
      name: row.name,
      displayOrder: row.display_order,
    }));
}
