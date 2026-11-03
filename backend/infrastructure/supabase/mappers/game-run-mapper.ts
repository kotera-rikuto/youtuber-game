import "server-only";

import type { GameRun, GameRunStatus } from "@/backend/domain/game/game-run";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import {
  parseDate,
  requireArray,
  requireBoolean,
  requireFiniteNumber,
  requireNonnegativeInteger,
  requirePositiveInteger,
  requireRecord,
  requireString,
} from "@/backend/infrastructure/supabase/mappers/validation";

type CurrentGameRow =
  Database["public"]["Views"]["current_game_view"]["Row"];
type GameRunRow = Database["public"]["Tables"]["game_runs"]["Row"];
export type OwnedGameRunRow = Pick<
  GameRunRow,
  "id" | "user_id" | "rule_set_id" | "status"
>;

const gameRunStatuses = new Set<GameRunStatus>([
  "playing",
  "stage_cleared",
  "cleared",
  "game_over",
  "abandoned",
]);

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
    status: mapGameRunStatus(row.status),
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

function mapGameRunStatus(value: string): GameRunStatus {
  if (!gameRunStatuses.has(value as GameRunStatus)) {
    throw new DataIntegrityError("status contains an unsupported value.");
  }

  return value as GameRunStatus;
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
