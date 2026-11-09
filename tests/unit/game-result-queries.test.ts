import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { FinalGameRun, GameRun } from "@/backend/domain/game/game-run";
import { mapFinalGame, type FinalGameRows } from "@/backend/infrastructure/supabase/mappers/game-run-mapper";
import {
  mapCurrentGameDTO,
  mapFinalResultDTO,
} from "@/backend/queries/game-result-dtos";
import { GameResultQueryError } from "@/backend/queries/game-result-query-error";
import { getCurrentGameDTO } from "@/backend/queries/get-current-game";
import { getCurrentGoalDTO } from "@/backend/queries/get-current-goal";
import { getFinalResultDTO } from "@/backend/queries/get-final-result";

vi.mock("server-only", () => ({}));

const context = { actorUserId: "owner" as UseCaseContext["actorUserId"] };

describe("game result queries", () => {
  it("returns the current game and stable ability/equipment order", async () => {
    const source = sourceFor({
      current: gameRun({ status: "playing", currentWeek: 156, subscribers: 150 }),
    });
    const result = await getCurrentGameDTO(context, "run-1", source);

    expect(result.status).toBe("playing");
    expect(result.abilities.map((ability) => ability.code)).toEqual([
      "planning",
      "talking",
      "expertise",
      "editing",
      "visual",
      "filming",
    ]);
    expect(result.equipment.map((equipment) => equipment.typeCode)).toEqual([
      "camera",
      "microphone",
      "editing_pc",
    ]);
    expect(JSON.stringify(result)).not.toMatch(/ownerUserId|ruleSetId|evaluation|score|prompt/);
  });

  it("returns stage_cleared as current and includes the current goal", async () => {
    const source = sourceFor({
      current: gameRun({ status: "stage_cleared", subscribers: 100 }),
    });
    const result = await getCurrentGoalDTO(context, "run-1", source);
    expect(result).toMatchObject({
      runId: "run-1",
      currentWeek: 10,
      remainingWeeks: 1,
      progressRate: 100,
    });
  });

  it("does not distinguish another user's run from a missing run", async () => {
    const source = sourceFor({ current: null });
    await expect(getCurrentGameDTO(context, "other-run", source)).rejects.toMatchObject({
      code: "NOT_FOUND",
    } satisfies Partial<GameResultQueryError>);
  });

  it("handles missing goals and clamps progress at 100 percent", async () => {
    const noGoal = sourceFor({ current: gameRun({ currentGoal: null }) });
    await expect(getCurrentGoalDTO(context, "run-1", noGoal)).resolves.toBeNull();

    const overTarget = gameRun({ subscribers: 200 });
    expect(mapCurrentGameDTO(overTarget).currentGoal?.progressRate).toBe(100);
  });

  it("rejects an active goal after its deadline", async () => {
    const source = sourceFor({
      current: gameRun({ currentWeek: 11 }),
    });
    await expect(getCurrentGoalDTO(context, "run-1", source)).rejects.toMatchObject({
      code: "INVALID_STATE",
    });
  });

  it.each(["cleared", "game_over", "abandoned"] as const)(
    "returns a final result for %s",
    async (status) => {
      const final = finalGame({ status });
      const result = await getFinalResultDTO(context, "run-1", sourceFor({ final }));
      expect(result.finalStatus).toBe(status);
      expect(result.elapsedWeeks).toBe(104);
      expect(result.elapsedYears).toBe(2);
    },
  );

  it("returns the four non-cleared termination reasons and null for cleared", () => {
    for (const reason of ["death", "flame_ban", "deadline", "abandoned"] as const) {
      expect(mapFinalResultDTO(finalGame({ status: "game_over", reason })).terminationReason).toBe(reason);
    }
    expect(mapFinalResultDTO(finalGame({ status: "cleared", reason: null })).terminationReason).toBeNull();
  });

  it("rejects a final query for an active game", async () => {
    await expect(
      getFinalResultDTO(context, "run-1", sourceFor({ final: finalGame({ status: "playing" }) })),
    ).rejects.toMatchObject({ code: "INVALID_STATE" });
  });

  it("rejects contradictory termination history in the mapper", () => {
    const rows = finalRows({
      gameRun: { status: "game_over" },
      terminations: [terminationRow("death"), terminationRow("deadline")],
    });
    expect(() => mapFinalGame(rows)).toThrow();
  });
});

function sourceFor(values: { current?: GameRun | null; final?: FinalGameRun | null }) {
  return {
    findCurrentById: async () => values.current ?? null,
    findFinalById: async () => values.final ?? null,
  };
}

function gameRun(overrides: Partial<{
  status: GameRun["status"];
  currentWeek: number;
  subscribers: number;
  currentGoal: GameRun["currentGoal"];
}> = {}): GameRun {
  return {
    id: "run-1",
    ownerUserId: "owner",
    ruleSetId: "internal-rule",
    channelName: "Channel",
    channelType: { code: "mainstream", name: "王道系" },
    specialty: null,
    status: overrides.status ?? "playing",
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
    completedAt: null,
    currentState: {
      currentWeek: overrides.currentWeek ?? 10,
      stateVersion: 4,
      postingFrequency: 3,
      cash: 100_000,
      energy: 80,
      subscribers: overrides.subscribers ?? 50,
      cumulativeViews: 123_456,
      flameCount: 1,
      updatedAt: new Date("2026-01-02T00:00:00.000Z"),
    },
    abilities: [
      ["filming", "撮影技術"],
      ["planning", "企画力"],
      ["visual", "ビジュアル"],
      ["editing", "編集力"],
      ["expertise", "専門知識"],
      ["talking", "トーク力"],
    ].map(([code, name]) => ({ code, name, value: 10 })),
    equipment: [
      { typeCode: "editing_pc", typeName: "編集PC", tier: "beginner", viewBonus: 0.05, acquiredWeek: 1 },
      { typeCode: "camera", typeName: "カメラ", tier: "beginner", viewBonus: 0.05, acquiredWeek: 1 },
      { typeCode: "microphone", typeName: "マイク", tier: "beginner", viewBonus: 0.05, acquiredWeek: 1 },
    ],
    currentGoal: overrides.currentGoal === undefined ? {
      stageNumber: 1,
      targetSubscribers: 100,
      startedWeek: 1,
      deadlineWeek: 10,
      status: "active",
      isFinal: false,
    } : overrides.currentGoal,
    unlockedFeatures: [{ code: "ad_revenue", name: "広告収益", unlockedWeek: 1, activeFromWeek: 2 }],
  };
}

function finalGame(overrides: Partial<{
  status: FinalGameRun["status"];
  reason: "death" | "flame_ban" | "deadline" | "abandoned" | null;
}> = {}): FinalGameRun {
  const status = overrides.status ?? "game_over";
  return {
    ...gameRun({ status }),
    status,
    completedAt: new Date("2026-01-01T00:00:00.000Z"),
    currentState: { ...gameRun().currentState, currentWeek: 105 },
    termination: status === "cleared" || status === "playing" || status === "stage_cleared"
      ? null
      : { reason: overrides.reason ?? "death", occurredWeek: 104 },
    finalStage: {
      stageNumber: 2,
      targetSubscribers: 1_000_000,
      startedWeek: 1,
      deadlineWeek: 156,
      achievedWeek: status === "cleared" ? 104 : null,
      isFinal: status === "cleared",
    },
  };
}

function finalRows(overrides: {
  gameRun?: Partial<FinalGameRows["gameRun"]>;
  terminations?: FinalGameRows["terminations"];
} = {}): FinalGameRows {
  const rows: FinalGameRows = {
    gameRun: {
      id: "run-1",
      user_id: "owner",
      rule_set_id: "rules-1",
      channel_name: "Channel",
      status: "game_over",
      completed_at: "2026-01-01T00:00:00.000Z",
      specialty_code: null,
      channel_type_code: "mainstream",
    },
    state: {
      run_id: "run-1",
      current_week: 105,
      posting_frequency_rule_id: "frequency-3",
      cash: 1_000,
      energy: 10,
      subscribers: 100,
      cumulative_views: 2_000,
      flame_count: 1,
      state_version: 4,
      updated_at: "2026-01-01T00:00:00.000Z",
    },
    channelType: { code: "mainstream", name: "王道系" },
    specialty: null,
    terminations: [terminationRow("death")],
    goals: [{ started_week: 1, deadline_week: 156, status: "failed", achieved_week: null, stage_number: 1, target_subscribers: 100, is_final: false }],
  };
  return {
    ...rows,
    gameRun: { ...rows.gameRun, ...overrides.gameRun },
    terminations: overrides.terminations ?? rows.terminations,
  };
}

function terminationRow(reason: string) {
  return {
    id: crypto.randomUUID(),
    run_id: "run-1",
    execution_id: null,
    week_result_id: null,
    reason,
    occurred_week: 104,
    calculated_energy: 0,
    calculated_flame_count: 1,
    created_at: "2026-01-01T00:00:00.000Z",
  };
}
