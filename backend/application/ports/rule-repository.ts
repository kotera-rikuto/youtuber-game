import type {
  ChannelRule,
  PostingFrequencyRule,
  PublishedRuleSet,
  SpecialtyRule,
} from "@/backend/domain/game/rules";

export interface RuleRepository {
  findActiveRuleSet(): Promise<PublishedRuleSet | null>;
  findPublishedRuleSetById(ruleSetId: string): Promise<PublishedRuleSet | null>;
  listChannelRules(ruleSetId: string): Promise<readonly ChannelRule[]>;
  listSpecialties(ruleSetId: string): Promise<readonly SpecialtyRule[]>;
  listPostingFrequencies(
    ruleSetId: string,
  ): Promise<readonly PostingFrequencyRule[]>;
}
