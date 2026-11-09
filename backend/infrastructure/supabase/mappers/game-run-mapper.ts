import "server-only";

import type { FinalGameRun, GameRun } from "@/backend/domain/game/game-run";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import {
  parseDate,
  requireArray,
  requireBoolean,
  requireFiniteNumber,
  requireGameRunStatus,
  requireNonnegativeInteger,
  requirePositiveInteger,
  requireRecord,
  requireString,
} from "@/backend/infrastructure/supabase/mappers/validation";

type CurrentGameRow =
  Database["public"]["Views"]["current_game_view"]["Row"];
type GameRunRow = Database["public"]["Tables"]["game_runs"]["Row"];
type RunStateRow = Database["public"]["Tables"]["run_state"]["Row"];
type TerminationRow = Database["public"]["Tables"]["game_terminations"]["Row"];
type RunGoalRow = Database["public"]["Tables"]["run_goals"]["Row"];
type GoalRuleRow = Database["public"]["Tables"]["goal_rules"]["Row"];
type ChannelTypeRow = Database["public"]["Tables"]["channel_types"]["Row"];
export type OwnedGameRunRow = Pick<
  GameRunRow,
  "id" | "user_id" | "rule_set_id" | "status"
>;

export type FinalGameRows = {
  gameRun: Pick<
    GameRunRow,
    "id" | "user_id" | "rule_set_id" | "channel_name" | "status" | "completed_at" | "specialty_code"
  > & { channel_type_code: string };
  state: RunStateRow;
  channelType: Pick<ChannelTypeRow, "code" | "name">;
  specialty: { code: string; name: string } | null;
  terminations: readonly TerminationRow[];
  goals: readonly (Pick<RunGoalRow, "started_week" | "deadline_week" | "status" | "achieved_week"> &
    Pick<GoalRuleRow, "stage_number" | "target_subscribers" | "is_final">)[];
};

export function mapCurrentGame(
  row: CurrentGameRow,
  ownedRun: OwnedGameRunRow,
): GameRun {
  if (row.run_id !== ownedRun.id) {
    throw new DataIntegrityError("Current game row belongs to a different run.");
  }

  return {
    id: row.run_id,
    ownerUserId: ownedRun.user_id,
    ruleSetId: ownedRun.rule_set_id,
    channelName: requireString(row.channel_name, "channel_name"),
    channelType: {
      code: requireString(row.channel_type_code, "channel_type_code"),
      name: requireString(row.channel_type_name, "channel_type_name"),
    },
    specialty: mapSpecialty(row.specialty_code, row.specialty_name),
    status: requireGameRunStatus(row.status, "status"),
    createdAt: parseDate(row.created_at, "created_at"),
    completedAt:
      row.completed_at === null
        ? null
        : parseDate(row.completed_at, "completed_at"),
    currentState: {
      currentWeek: requirePositiveInteger(row.current_week, "current_week"),
      stateVersion: requireNonnegativeInteger(
        row.state_version,
        "state_version",
      ),
      postingFrequency: requirePositiveInteger(
        row.videos_per_week,
        "videos_per_week",
      ),
      cash: requireNonnegativeInteger(row.cash, "cash"),
      energy: requireNonnegativeInteger(row.energy, "energy"),
      subscribers: requireNonnegativeInteger(row.subscribers, "subscribers"),
      cumulativeViews: requireNonnegativeInteger(
        row.cumulative_views,
        "cumulative_views",
      ),
      flameCount: requireNonnegativeInteger(row.flame_count, "flame_count"),
      updatedAt: parseDate(row.updated_at, "updated_at"),
    },
    abilities: mapAbilities(row.abilities),
    equipment: mapEquipment(row.equipment),
    currentGoal: mapCurrentGoal(row),
    unlockedFeatures: mapFeatureUnlocks(row.feature_unlocks),
  };
}

export function mapFinalGame(rows: FinalGameRows): FinalGameRun {
  const status = requireGameRunStatus(rows.gameRun.status, "status");
  const terminalStatuses = new Set(["cleared", "game_over", "abandoned"]);
  if (status === "playing" || status === "stage_cleared") {
    return {
      id: requireString(rows.gameRun.id, "id"),
      ownerUserId: requireString(rows.gameRun.user_id, "user_id"),
      channelName: requireString(rows.gameRun.channel_name, "channel_name"),
      channelType: mapChannelType(rows.channelType),
      specialty: mapSpecialty(rows.specialty?.code ?? null, rows.specialty?.name ?? null),
      status,
      completedAt: rows.gameRun.completed_at === null ? null : parseDate(rows.gameRun.completed_at, "completed_at"),
      currentState: mapFinalState(rows.state),
      termination: null,
      finalStage: null,
    };
  }
  if (!terminalStatuses.has(status)) {
    throw new DataIntegrityError("Status is not a terminal game status.");
  }

  if (rows.terminations.length > 1) {
    throw new DataIntegrityError("A game run must have at most one termination.");
  }
  const termination = rows.terminations[0] ?? null;
  if (status === "cleared" && termination !== null) {
    throw new DataIntegrityError("A cleared game must not have a termination.");
  }
  if (status !== "cleared" && termination === null) {
    throw new DataIntegrityError("A terminal game must have a termination.");
  }

  return {
    id: requireString(rows.gameRun.id, "id"),
    ownerUserId: requireString(rows.gameRun.user_id, "user_id"),
    channelName: requireString(rows.gameRun.channel_name, "channel_name"),
    channelType: {
      code: requireString(rows.channelType.code, "channel_type_code"),
      name: requireString(rows.channelType.name, "channel_type_name"),
    },
    specialty: mapSpecialty(rows.specialty?.code ?? null, rows.specialty?.name ?? null),
    status,
    completedAt: rows.gameRun.completed_at === null ? null : parseDate(rows.gameRun.completed_at, "completed_at"),
    currentState: mapFinalState(rows.state),
    termination: termination === null ? null : {
      reason: requireTerminationReason(termination.reason),
      occurredWeek: requirePositiveInteger(termination.occurred_week, "occurred_week"),
    },
    finalStage: mapFinalStage(rows.goals),
  };
}

function mapChannelType(
  channelType: FinalGameRows["channelType"],
): GameRun["channelType"] {
  return {
    code: requireString(channelType.code, "channel_type_code"),
    name: requireString(channelType.name, "channel_type_name"),
  };
}

function mapFinalState(row: RunStateRow): FinalGameRun["currentState"] {
  return {
    currentWeek: requirePositiveInteger(row.current_week, "current_week"),
    cash: requireNonnegativeInteger(row.cash, "cash"),
    energy: requireNonnegativeInteger(row.energy, "energy"),
    subscribers: requireNonnegativeInteger(row.subscribers, "subscribers"),
    cumulativeViews: requireNonnegativeInteger(row.cumulative_views, "cumulative_views"),
    flameCount: requireNonnegativeInteger(row.flame_count, "flame_count"),
  };
}

function mapFinalStage(rows: FinalGameRows["goals"]): FinalGameRun["finalStage"] {
  if (rows.length === 0) return null;
  const stage = [...rows].sort((left, right) => right.stage_number - left.stage_number)[0];
  return {
    stageNumber: requirePositiveInteger(stage.stage_number, "stage_number"),
    targetSubscribers: requireNonnegativeInteger(stage.target_subscribers, "target_subscribers"),
    startedWeek: requirePositiveInteger(stage.started_week, "started_week"),
    deadlineWeek: requirePositiveInteger(stage.deadline_week, "deadline_week"),
    achievedWeek:
      stage.achieved_week === null
        ? null
        : requirePositiveInteger(stage.achieved_week, "achieved_week"),
    isFinal: requireBoolean(stage.is_final, "is_final"),
  };
}

function requireTerminationReason(
  value: unknown,
): NonNullable<FinalGameRun["termination"]>["reason"] {
  if (value === "death" || value === "flame_ban" || value === "deadline" || value === "abandoned") {
    return value;
  }
  throw new DataIntegrityError("reason contains an unsupported value.");
}

function mapSpecialty(
  code: string | null,
  name: string | null,
): GameRun["specialty"] {
  if (code === null && name === null) {
    return null;
  }
  if (code === null || name === null) {
    throw new DataIntegrityError("Specialty code and name must both be present.");
  }

  return {
    code: requireString(code, "specialty_code"),
    name: requireString(name, "specialty_name"),
  };
}

function mapAbilities(value: CurrentGameRow["abilities"]): GameRun["abilities"] {
  return requireArray(value, "abilities").map((item, index) => {
    const ability = requireRecord(item, `abilities[${index}]`);
    return {
      code: requireString(ability.code, `abilities[${index}].code`),
      name: requireString(ability.name, `abilities[${index}].name`),
      value: requireNonnegativeInteger(
        ability.value,
        `abilities[${index}].value`,
      ),
    };
  });
}

function mapEquipment(value: CurrentGameRow["equipment"]): GameRun["equipment"] {
  return requireArray(value, "equipment").map((item, index) => {
    const equipment = requireRecord(item, `equipment[${index}]`);
    return {
      typeCode: requireString(
        equipment.typeCode,
        `equipment[${index}].typeCode`,
      ),
      typeName: requireString(
        equipment.typeName,
        `equipment[${index}].typeName`,
      ),
      tier: requireString(equipment.tier, `equipment[${index}].tier`),
      viewBonus: requireFiniteNumber(
        equipment.viewBonus,
        `equipment[${index}].viewBonus`,
      ),
      acquiredWeek: requireNonnegativeInteger(
        equipment.acquiredWeek,
        `equipment[${index}].acquiredWeek`,
      ),
    };
  });
}

function mapCurrentGoal(row: CurrentGameRow): GameRun["currentGoal"] {
  const values = [
    row.current_stage_number,
    row.current_goal_target_subscribers,
    row.current_goal_started_week,
    row.current_goal_deadline_week,
    row.current_goal_status,
    row.is_current_goal_final,
  ];
  if (values.every((value) => value === null)) {
    return null;
  }
  if (values.some((value) => value === null)) {
    throw new DataIntegrityError("Current goal fields must be present together.");
  }
  if (row.current_goal_status !== "active") {
    throw new DataIntegrityError("Current goal must have active status.");
  }

  return {
    stageNumber: requirePositiveInteger(
      row.current_stage_number,
      "current_stage_number",
    ),
    targetSubscribers: requirePositiveInteger(
      row.current_goal_target_subscribers,
      "current_goal_target_subscribers",
    ),
    startedWeek: requirePositiveInteger(
      row.current_goal_started_week,
      "current_goal_started_week",
    ),
    deadlineWeek: requirePositiveInteger(
      row.current_goal_deadline_week,
      "current_goal_deadline_week",
    ),
    status: "active",
    isFinal: requireBoolean(row.is_current_goal_final, "is_current_goal_final"),
  };
}

function mapFeatureUnlocks(
  value: CurrentGameRow["feature_unlocks"],
): GameRun["unlockedFeatures"] {
  return requireArray(value, "feature_unlocks").map((item, index) => {
    const feature = requireRecord(item, `feature_unlocks[${index}]`);
    return {
      code: requireString(feature.code, `feature_unlocks[${index}].code`),
      name: requireString(feature.name, `feature_unlocks[${index}].name`),
      unlockedWeek: requirePositiveInteger(
        feature.unlockedWeek,
        `feature_unlocks[${index}].unlockedWeek`,
      ),
      activeFromWeek: requirePositiveInteger(
        feature.activeFromWeek,
        `feature_unlocks[${index}].activeFromWeek`,
      ),
    };
  });
}
