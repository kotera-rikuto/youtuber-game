import type { FinalGameRun, GameRun } from "@/backend/domain/game/game-run";

export type PublicAbilityDTO = {
  code: string;
  name: string;
  value: number;
};

export type PublicEquipmentDTO = {
  typeCode: string;
  typeName: string;
  tier: string;
  acquiredWeek: number;
};

export type CurrentGoalDTO = {
  runId: string;
  stageNumber: number;
  targetSubscribers: number;
  currentSubscribers: number;
  startedWeek: number;
  deadlineWeek: number;
  currentWeek: number;
  remainingWeeks: number;
  progressRate: number;
  isFinal: boolean;
};

export type CurrentGameDTO = {
  runId: string;
  channelName: string;
  channelType: { code: string; name: string };
  specialty: { code: string; name: string } | null;
  status: "playing" | "stage_cleared";
  currentWeek: number;
  stateVersion: number;
  postingFrequency: number;
  cash: number;
  energy: number;
  subscribers: number;
  cumulativeViews: number;
  flameCount: number;
  abilities: readonly PublicAbilityDTO[];
  equipment: readonly PublicEquipmentDTO[];
  currentGoal: CurrentGoalDTO | null;
  unlockedFeatures: readonly {
    code: string;
    name: string;
    activeFromWeek: number;
  }[];
};

export type FinalResultDTO = {
  runId: string;
  channelName: string;
  channelType: { code: string; name: string };
  specialty: { code: string; name: string } | null;
  finalStatus: "cleared" | "game_over" | "abandoned";
  terminationReason: "death" | "flame_ban" | "deadline" | "abandoned" | null;
  finalSubscribers: number;
  cumulativeViews: number;
  finalCash: number;
  finalEnergy: number;
  elapsedWeeks: number;
  elapsedYears: number;
  flameCount: number;
  completedAt: Date;
  finalStage: {
    stageNumber: number;
    targetSubscribers: number;
    achievedWeek: number | null;
    isFinal: boolean;
  } | null;
};

export function mapCurrentGameDTO(game: GameRun): CurrentGameDTO {
  if (game.status !== "playing" && game.status !== "stage_cleared") {
    throw new Error("Current game must be playable.");
  }

  return {
    runId: game.id,
    channelName: game.channelName,
    channelType: game.channelType,
    specialty: game.specialty,
    status: game.status,
    currentWeek: game.currentState.currentWeek,
    stateVersion: game.currentState.stateVersion,
    postingFrequency: game.currentState.postingFrequency,
    cash: game.currentState.cash,
    energy: game.currentState.energy,
    subscribers: game.currentState.subscribers,
    cumulativeViews: game.currentState.cumulativeViews,
    flameCount: game.currentState.flameCount,
    abilities: [...game.abilities]
      .sort((left, right) => abilityOrder(left.code) - abilityOrder(right.code))
      .map(({ code, name, value }) => ({ code, name, value })),
    equipment: [...game.equipment]
      .sort((left, right) => equipmentOrder(left.typeCode) - equipmentOrder(right.typeCode))
      .map(({ typeCode, typeName, tier, acquiredWeek }) => ({
        typeCode,
        typeName,
        tier,
        acquiredWeek,
      })),
    currentGoal: game.currentGoal
      ? mapCurrentGoal(game.id, game.currentState.currentWeek, game.currentState.subscribers, game.currentGoal)
      : null,
    unlockedFeatures: [...game.unlockedFeatures]
      .sort((left, right) => left.code.localeCompare(right.code))
      .map(({ code, name, activeFromWeek }) => ({ code, name, activeFromWeek })),
  };
}

export function mapCurrentGoalDTO(game: GameRun): CurrentGoalDTO | null {
  return game.currentGoal
    ? mapCurrentGoal(game.id, game.currentState.currentWeek, game.currentState.subscribers, game.currentGoal)
    : null;
}

function mapCurrentGoal(
  runId: string,
  currentWeek: number,
  currentSubscribers: number,
  goal: NonNullable<GameRun["currentGoal"]>,
): CurrentGoalDTO {
  const remainingWeeks = Math.max(0, goal.deadlineWeek - currentWeek + 1);
  const progressRate = Math.min(
    100,
    Math.max(0, (currentSubscribers / goal.targetSubscribers) * 100),
  );
  return {
    runId,
    stageNumber: goal.stageNumber,
    targetSubscribers: goal.targetSubscribers,
    currentSubscribers,
    startedWeek: goal.startedWeek,
    deadlineWeek: goal.deadlineWeek,
    currentWeek,
    remainingWeeks,
    progressRate,
    isFinal: goal.isFinal,
  };
}

export function mapFinalResultDTO(game: FinalGameRun): FinalResultDTO {
  if (game.status !== "cleared" && game.status !== "game_over" && game.status !== "abandoned") {
    throw new Error("Final result must be terminal.");
  }
  if (!game.completedAt) {
    throw new Error("A final result must have completedAt.");
  }

  const elapsedWeeks = game.termination?.occurredWeek ?? game.finalStage?.achievedWeek ?? Math.max(0, game.currentState.currentWeek - 1);
  return {
    runId: game.id,
    channelName: game.channelName,
    channelType: game.channelType,
    specialty: game.specialty,
    finalStatus: game.status,
    terminationReason: game.termination?.reason ?? null,
    finalSubscribers: game.currentState.subscribers,
    cumulativeViews: game.currentState.cumulativeViews,
    finalCash: game.currentState.cash,
    finalEnergy: game.currentState.energy,
    elapsedWeeks,
    elapsedYears: Math.floor(elapsedWeeks / 52),
    flameCount: game.currentState.flameCount,
    completedAt: game.completedAt,
    finalStage: game.finalStage
      ? {
          stageNumber: game.finalStage.stageNumber,
          targetSubscribers: game.finalStage.targetSubscribers,
          achievedWeek: game.finalStage.achievedWeek,
          isFinal: game.finalStage.isFinal,
        }
      : null,
  };
}

const abilityOrderMap = new Map([
  ["planning", 1],
  ["talking", 2],
  ["expertise", 3],
  ["editing", 4],
  ["visual", 5],
  ["filming", 6],
]);

function abilityOrder(code: string): number {
  return abilityOrderMap.get(code) ?? Number.MAX_SAFE_INTEGER;
}

const equipmentOrderMap = new Map([
  ["camera", 1],
  ["microphone", 2],
  ["editing_pc", 3],
]);

function equipmentOrder(code: string): number {
  return equipmentOrderMap.get(code) ?? Number.MAX_SAFE_INTEGER;
}
