import { describe, expect, it, vi } from "vitest";

import {
  GAME_RUN_STATUSES,
  type GameRunStatus,
} from "@/backend/domain/game/game-run";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { mapCurrentGame } from "@/backend/infrastructure/supabase/mappers/game-run-mapper";
import { mapIdeaQueue } from "@/backend/infrastructure/supabase/mappers/idea-stock-mapper";
import {
  mapPostingFrequencyRule,
  mapPublishedRuleSet,
} from "@/backend/infrastructure/supabase/mappers/rule-mapper";
import { mapWeekResult } from "@/backend/infrastructure/supabase/mappers/week-result-mapper";

vi.mock("server-only", () => ({}));

type CurrentGameRow =
  Database["public"]["Views"]["current_game_view"]["Row"];
type IdeaStockRow =
  Database["public"]["Views"]["idea_stock_view"]["Row"];
type WeekHistoryRow =
  Database["public"]["Views"]["week_history_view"]["Row"];
type RuleSetRow = Database["public"]["Tables"]["rule_sets"]["Row"];
type PostingFrequencyRow =
  Database["public"]["Tables"]["posting_frequency_rules"]["Row"];

describe("repository row mappers", () => {
  it("maps the current game view into a DB-independent aggregate", () => {
    const game = mapCurrentGame(currentGameRow(), {
      id: "run-1",
      user_id: "user-1",
      rule_set_id: "rules-1",
      status: "playing",
    });

    expect(game).toMatchObject({
      id: "run-1",
      ownerUserId: "user-1",
      ruleSetId: "rules-1",
      specialty: { code: "gaming", name: "ゲーム" },
      currentState: {
        currentWeek: 2,
        stateVersion: 3,
        postingFrequency: 3,
      },
      abilities: [{ code: "planning", name: "企画力", value: 20 }],
      equipment: [{ typeCode: "camera", tier: "beginner" }],
      currentGoal: { stageNumber: 1, status: "active" },
      unlockedFeatures: [{ code: "ad_revenue", activeFromWeek: 2 }],
    });
    expect(game.createdAt).toEqual(new Date("2026-11-01T00:00:00.000Z"));
  });

  it("maps a nullable specialty and goal only when all related fields are null", () => {
    const row = currentGameRow({
      specialty_code: null,
      specialty_name: null,
      current_stage_number: null,
      current_goal_target_subscribers: null,
      current_goal_started_week: null,
      current_goal_deadline_week: null,
      current_goal_status: null,
      is_current_goal_final: null,
    });

    const game = mapCurrentGame(row, {
      id: "run-1",
      user_id: "user-1",
      rule_set_id: "rules-1",
      status: "stage_cleared",
    });

    expect(game.specialty).toBeNull();
    expect(game.currentGoal).toBeNull();
  });

  it("rejects inconsistent nullable current-game fields", () => {
    const row = currentGameRow({ specialty_name: null });

    expect(() =>
      mapCurrentGame(row, {
        id: "run-1",
        user_id: "user-1",
        rule_set_id: "rules-1",
        status: "playing",
      }),
    ).toThrow(DataIntegrityError);
  });

  it("rejects malformed JSON children instead of asserting their shape", () => {
    const row = currentGameRow({ abilities: [{ code: "planning" }] });

    expect(() =>
      mapCurrentGame(row, {
        id: "run-1",
        user_id: "user-1",
        rule_set_id: "rules-1",
        status: "playing",
      }),
    ).toThrow("abilities[0].name");
  });

  it("maps idea rows in queue order", () => {
    const queue = mapIdeaQueue("run-1", [ideaStockRow(1), ideaStockRow(2)]);

    expect(queue.items.map((idea) => idea.position)).toEqual([1, 2]);
    expect(queue.items[0]?.createdAt).toBeInstanceOf(Date);
  });

  it("rejects duplicate or missing idea queue positions", () => {
    expect(() =>
      mapIdeaQueue("run-1", [ideaStockRow(1), ideaStockRow(3)]),
    ).toThrow("contiguous");
  });

  it("maps published and posting-frequency rules", () => {
    expect(mapPublishedRuleSet(ruleSetRow())).toMatchObject({
      id: "rules-1",
      version: "1.0.0",
      status: "active",
    });
    expect(mapPostingFrequencyRule(postingFrequencyRow())).toEqual({
      id: "frequency-3",
      ruleSetId: "rules-1",
      videosPerWeek: 3,
      viewMultiplier: 0.9,
      energyCost: 30,
      abilityPointsAwarded: 3,
    });
  });

  it("rejects a draft rule set", () => {
    expect(() =>
      mapPublishedRuleSet({
        ...ruleSetRow(),
        status: "draft",
        published_at: null,
      }),
    ).toThrow(DataIntegrityError);
  });

  it("maps a week-history row and its event JSON", () => {
    const result = mapWeekResult(weekHistoryRow());

    expect(result).toMatchObject({
      id: "week-result-1",
      weekNumber: 1,
      action: { code: "rest", name: "休む" },
      subscriberChange: 20,
      events: [
        {
          code: "viral",
          sequenceNumber: 1,
          displayMetadata: { label: "急上昇" },
        },
      ],
    });
  });

  it.each(GAME_RUN_STATUSES)(
    "accepts the valid game-run status %s in a week result",
    (status) => {
      const result = mapWeekResult(weekHistoryRow({ run_status_after: status }));
      expectGameRunStatus(result.runStatusAfter);
      expect(result.runStatusAfter).toBe(status);
    },
  );

  it("rejects an unknown game-run status in a week result", () => {
    expect(() =>
      mapWeekResult(weekHistoryRow({ run_status_after: "unknown" })),
    ).toThrow("run_status_after contains an unsupported value");
  });

  it("accepts the nullable action and posting frequency of an unavailable week", () => {
    const row = weekHistoryRow({
      action_code: null,
      action_name: null,
      planned_video_count: null,
      health_condition_started: false,
      health_condition_duration_weeks: null,
      unavailable_from_week: null,
      unavailable_through_week: null,
    });

    expect(mapWeekResult(row)).toMatchObject({
      action: null,
      plannedVideoCount: null,
      healthCondition: null,
    });
  });

  it("rejects an incomplete health-condition row", () => {
    const row = weekHistoryRow({ unavailable_through_week: null });
    expect(() => mapWeekResult(row)).toThrow(DataIntegrityError);
  });
});

function currentGameRow(
  overrides: Partial<CurrentGameRow> = {},
): CurrentGameRow {
  return {
    run_id: "run-1",
    channel_type_code: "specialized",
    channel_type_name: "特化系",
    specialty_code: "gaming",
    specialty_name: "ゲーム",
    channel_name: "テストチャンネル",
    status: "playing",
    created_at: "2026-11-01T00:00:00.000Z",
    completed_at: null,
    current_week: 2,
    videos_per_week: 3,
    cash: 1000,
    energy: 80,
    subscribers: 120,
    cumulative_views: 5000,
    flame_count: 0,
    state_version: 3,
    updated_at: "2026-11-02T00:00:00.000Z",
    abilities: [{ code: "planning", name: "企画力", value: 20 }],
    equipment: [
      {
        typeCode: "camera",
        typeName: "カメラ",
        tier: "beginner",
        viewBonus: 0.05,
        acquiredWeek: 1,
      },
    ],
    current_stage_number: 1,
    current_goal_target_subscribers: 1000,
    current_goal_started_week: 1,
    current_goal_deadline_week: 156,
    current_goal_status: "active",
    is_current_goal_final: false,
    feature_unlocks: [
      {
        code: "ad_revenue",
        name: "広告収益",
        unlockedWeek: 1,
        activeFromWeek: 2,
      },
    ],
    ...overrides,
  };
}

function ideaStockRow(position: number): IdeaStockRow {
  return {
    run_id: "run-1",
    idea_id: `idea-${position}`,
    idea_source: "player",
    position,
    title: `企画${position}`,
    description: null,
    created_week: 1,
    created_at: "2026-11-01T00:00:00.000Z",
    queued_at: "2026-11-01T00:01:00.000Z",
    stock_status: "queued",
    is_pending: true,
  };
}

function ruleSetRow(): RuleSetRow {
  return {
    id: "rules-1",
    version: "1.0.0",
    status: "active",
    published_at: "2026-11-01T00:00:00.000Z",
    created_at: "2026-10-01T00:00:00.000Z",
  };
}

function postingFrequencyRow(): PostingFrequencyRow {
  return {
    id: "frequency-3",
    rule_set_id: "rules-1",
    videos_per_week: 3,
    view_multiplier: 0.9,
    energy_cost: 30,
    ability_points_awarded: 3,
  };
}

function weekHistoryRow(
  overrides: Partial<WeekHistoryRow> = {},
): WeekHistoryRow {
  return {
    run_id: "run-1",
    week_result_id: "week-result-1",
    week_number: 1,
    stage_number: 1,
    action_code: "rest",
    action_name: "休む",
    planned_video_count: 1,
    posted_video_count: 1,
    views_before_event: 100,
    final_views: 120,
    event_view_change: 20,
    subscribers_before: 10,
    max_subscribers_during_week: 30,
    subscribers_after: 30,
    subscriber_change: 20,
    energy_before: 100,
    energy_after: 90,
    energy_change: -10,
    cash_before: 1000,
    cash_after: 1024,
    cash_change: 24,
    ad_revenue: 24,
    flame_count_before: 0,
    flame_count_after: 0,
    flame_count_change: 0,
    had_flame: false,
    health_condition_started: true,
    health_condition_duration_weeks: 2,
    unavailable_from_week: 2,
    unavailable_through_week: 3,
    was_activity_unavailable: false,
    run_status_after: "playing",
    state_version_after: 1,
    created_at: "2026-11-01T00:00:00.000Z",
    events: [
      {
        code: "viral",
        name: "バズ",
        sequenceNumber: 1,
        displayMetadata: { label: "急上昇" },
      },
    ],
    ...overrides,
  };
}

function expectGameRunStatus(status: GameRunStatus): void {
  expect(GAME_RUN_STATUSES).toContain(status);
}
