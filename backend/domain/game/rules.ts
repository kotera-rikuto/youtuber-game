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
