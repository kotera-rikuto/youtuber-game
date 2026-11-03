export const POSTING_STYLES = [
  "mainstream",
  "specialized",
  "controversial",
  "idol",
] as const;

export type PostingStyle = (typeof POSTING_STYLES)[number];

export const SPECIALTY_CODES = [
  "baseball",
  "soccer",
  "gaming",
  "pc_gadgets",
  "science",
  "history_culture",
  "occult",
  "nature",
  "food_culture",
  "outdoor_survival",
] as const;

export type SpecialtyCode = (typeof SPECIALTY_CODES)[number];

export type PublishedRuleSet = {
  id: string;
  version: string;
  status: "active" | "retired";
  publishedAt: Date;
};

export type ChannelRule = {
  id: string;
  ruleSetId: string;
  channelTypeCode: string;
  viewMultiplier: number;
  weeklyFlameProbability: number;
};

export type SpecialtyRule = {
  ruleSetId: string;
  specialtyCode: string;
};

export type PostingFrequencyRule = {
  id: string;
  ruleSetId: string;
  videosPerWeek: number;
  viewMultiplier: number;
  energyCost: number;
  abilityPointsAwarded: number;
};
