export type GameRunStatus =
  | "playing"
  | "stage_cleared"
  | "cleared"
  | "game_over"
  | "abandoned";

export type RunAbility = {
  code: string;
  name: string;
  value: number;
};

export type RunEquipment = {
  typeCode: string;
  typeName: string;
  tier: string;
  viewBonus: number;
  acquiredWeek: number;
};

export type RunGoal = {
  stageNumber: number;
  targetSubscribers: number;
  startedWeek: number;
  deadlineWeek: number;
  status: "active";
  isFinal: boolean;
};

export type UnlockedFeature = {
  code: string;
  name: string;
  unlockedWeek: number;
  activeFromWeek: number;
};

export type GameRun = {
  id: string;
  ownerUserId: string;
  ruleSetId: string;
  channelName: string;
  channelType: {
    code: string;
    name: string;
  };
  specialty: {
    code: string;
    name: string;
  } | null;
  status: GameRunStatus;
  createdAt: Date;
  completedAt: Date | null;
  currentState: {
    currentWeek: number;
    stateVersion: number;
    postingFrequency: number;
    cash: number;
    energy: number;
    subscribers: number;
    cumulativeViews: number;
    flameCount: number;
    updatedAt: Date;
  };
  abilities: readonly RunAbility[];
  equipment: readonly RunEquipment[];
  currentGoal: RunGoal | null;
  unlockedFeatures: readonly UnlockedFeature[];
};
