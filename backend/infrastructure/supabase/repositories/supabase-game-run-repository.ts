import "server-only";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  StartGameCommitError,
  type GameRunRepository,
  type StartGameCommand,
  type StartGameCommitResult,
} from "@/backend/application/ports/game-run-repository";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import type { GameRun } from "@/backend/domain/game/game-run";
import {
  mapFinalGame,
  mapCurrentGame,
  type FinalGameRows,
  type OwnedGameRunRow,
} from "@/backend/infrastructure/supabase/mappers/game-run-mapper";
import {
  type DatabaseClient,
  findOwnedRun,
  mapRepositoryData,
} from "@/backend/infrastructure/supabase/repositories/repository-support";

const currentStatuses = ["playing", "stage_cleared"];

export class SupabaseGameRunRepository implements GameRunRepository {
  constructor(private readonly client: DatabaseClient) {}

  async findActiveByOwner(
    actorUserId: UseCaseContext["actorUserId"],
  ): Promise<GameRun | null> {
    const operation = "gameRun.findActiveByOwner";
    const { data, error } = await this.client
      .from("game_runs")
      .select("id,user_id,rule_set_id,status")
      .eq("user_id", actorUserId)
      .in("status", currentStatuses)
      .maybeSingle();

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (!data) {
      return null;
    }

    return this.getCurrentGame(data, operation);
  }

  async findCurrentById(query: OwnedRunQuery): Promise<GameRun | null> {
    const operation = "gameRun.findCurrentById";
    const ownedRun = await findOwnedRun(
      this.client,
      query.actorUserId,
      query.runId,
      operation,
    );
    if (!ownedRun || !currentStatuses.includes(ownedRun.status)) {
      return null;
    }

    return this.getCurrentGame(ownedRun, operation);
  }

  async findFinalById(query: OwnedRunQuery) {
    const operation = "gameRun.findFinalById";
    const [gameRunResponse, stateResponse, terminationResponse, goalsResponse] =
      await Promise.all([
        this.client
          .from("game_runs")
          .select("id,user_id,rule_set_id,channel_rule_id,channel_name,status,completed_at,specialty_code")
          .eq("id", query.runId)
          .eq("user_id", query.actorUserId)
          .maybeSingle(),
        this.client
          .from("run_state")
          .select("run_id,current_week,posting_frequency_rule_id,cash,energy,subscribers,cumulative_views,flame_count,state_version,updated_at")
          .eq("run_id", query.runId)
          .maybeSingle(),
        this.client
          .from("game_terminations")
          .select("id,run_id,execution_id,week_result_id,reason,occurred_week,calculated_energy,calculated_flame_count,created_at")
          .eq("run_id", query.runId),
        this.client
          .from("run_goals")
          .select("id,run_id,goal_rule_id,started_week,deadline_week,achieved_week,status")
          .eq("run_id", query.runId),
      ]);

    if (
      gameRunResponse.error ||
      stateResponse.error ||
      terminationResponse.error ||
      goalsResponse.error
    ) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (!gameRunResponse.data) {
      return null;
    }
    if (!stateResponse.data) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    const gameRun = gameRunResponse.data;
    const [channelRuleResponse, specialtyResponse, goalRulesResponse] =
      await Promise.all([
        this.client
          .from("channel_rules")
          .select("channel_type_code")
          .eq("id", gameRun.channel_rule_id)
          .eq("rule_set_id", gameRun.rule_set_id)
          .maybeSingle(),
        gameRun.specialty_code === null
          ? Promise.resolve({ data: null, error: null })
          : this.client
              .from("specialty_categories")
              .select("code,name")
              .eq("code", gameRun.specialty_code)
              .maybeSingle(),
        this.client
          .from("goal_rules")
          .select("id,stage_number,target_subscribers,is_final")
          .eq("rule_set_id", gameRun.rule_set_id),
      ]);

    if (
      channelRuleResponse.error ||
      specialtyResponse.error ||
      goalRulesResponse.error
    ) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (!channelRuleResponse.data || goalRulesResponse.data === null) {
      throw new RepositoryError("INVALID_DATA", operation);
    }
    if (gameRun.specialty_code !== null && !specialtyResponse.data) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    const channelTypeResponseWithCode = await this.client
      .from("channel_types")
      .select("code,name")
      .eq("code", channelRuleResponse.data.channel_type_code)
      .maybeSingle();
    if (channelTypeResponseWithCode.error || !channelTypeResponseWithCode.data) {
      throw new RepositoryError(
        channelTypeResponseWithCode.error ? "QUERY_FAILED" : "INVALID_DATA",
        operation,
      );
    }

    const goalRules = new Map(
      goalRulesResponse.data.map((rule) => [rule.id, rule]),
    );
    if (goalsResponse.data.some((goal) => !goalRules.has(goal.goal_rule_id))) {
      throw new RepositoryError("INVALID_DATA", operation);
    }
    const rows: FinalGameRows = {
      gameRun: {
        ...gameRun,
        channel_type_code: channelRuleResponse.data.channel_type_code,
      },
      state: stateResponse.data,
      channelType: channelTypeResponseWithCode.data,
      specialty: specialtyResponse.data,
      terminations: terminationResponse.data,
      goals: goalsResponse.data.map((goal) => ({
        ...goal,
        ...goalRules.get(goal.goal_rule_id)!,
      })),
    };

    return mapRepositoryData(operation, () => mapFinalGame(rows));
  }

  async commitStartGame(
    command: StartGameCommand,
  ): Promise<StartGameCommitResult> {
    const { data, error } = await this.client.rpc("commit_start_game", {
      p_actor_user_id: command.actorUserId,
      p_channel_name: command.channelName,
      p_posting_style: command.postingStyle,
      ...(command.specialtyCode
        ? { p_specialty_code: command.specialtyCode }
        : {}),
    });

    if (error) {
      throw mapStartGameRpcError(error.code, error.message);
    }
    if (typeof data !== "string" || data.length === 0) {
      throw new StartGameCommitError("COMMIT_FAILED");
    }

    return { runId: data };
  }

  private async getCurrentGame(
    ownedRun: OwnedGameRunRow,
    operation: string,
  ): Promise<GameRun> {
    const { data, error } = await this.client
      .from("current_game_view")
      .select(
        "run_id,channel_type_code,channel_type_name,specialty_code,specialty_name,channel_name,status,created_at,completed_at,current_week,videos_per_week,cash,energy,subscribers,cumulative_views,flame_count,state_version,updated_at,abilities,equipment,current_stage_number,current_goal_target_subscribers,current_goal_started_week,current_goal_deadline_week,current_goal_status,is_current_goal_final,feature_unlocks",
      )
      .eq("run_id", ownedRun.id)
      .maybeSingle();

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (!data) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    return mapRepositoryData(operation, () => mapCurrentGame(data, ownedRun));
  }
}

const startGameErrorCodes = new Map<string, StartGameCommitError["code"]>([
  ["START_GAME_ACTIVE_GAME_EXISTS", "ACTIVE_GAME_EXISTS"],
  ["START_GAME_RULES_UNAVAILABLE", "RULES_UNAVAILABLE"],
  ["START_GAME_SPECIALTY_REQUIRED", "SPECIALTY_REQUIRED"],
  ["START_GAME_SPECIALTY_NOT_ALLOWED", "SPECIALTY_NOT_ALLOWED"],
  ["START_GAME_VALIDATION_ERROR", "VALIDATION_ERROR"],
]);

function mapStartGameRpcError(code: string, message: string) {
  if (code === "23505") {
    return new StartGameCommitError("ACTIVE_GAME_EXISTS");
  }

  const mappedCode = startGameErrorCodes.get(message);
  return new StartGameCommitError(mappedCode ?? "COMMIT_FAILED");
}
