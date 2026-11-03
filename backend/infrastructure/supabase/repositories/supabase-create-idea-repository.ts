import "server-only";

import {
  CommitCreateIdeaError,
  type CommitCreateIdeaCommand,
  type CreateIdeaCapacity,
  type CreateIdeaCapacityQuery,
  type CreateIdeaRepository,
  type CreateIdeaRunLookup,
} from "@/backend/application/ports/create-idea-repository";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import {
  isGameRunStatus,
  type GameRunStatus,
} from "@/backend/domain/game/game-run";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseCreateIdeaRepository implements CreateIdeaRepository {
  constructor(private readonly client: DatabaseClient) {}

  async findRun(query: OwnedRunQuery): Promise<CreateIdeaRunLookup> {
    const operation = "createIdea.findRun";
    const { data: run, error: runError } = await this.client
      .from("game_runs")
      .select("user_id,rule_set_id,channel_rule_id,specialty_code,status")
      .eq("id", query.runId)
      .maybeSingle();

    assertQuerySucceeded(runError, operation);
    if (!run) {
      return { status: "not_found" };
    }
    if (run.user_id !== query.actorUserId) {
      return { status: "forbidden" };
    }
    if (!isGameRunStatus(run.status)) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    const [stateResult, channelResult, specialtyResult] = await Promise.all([
      this.client
        .from("run_state")
        .select("current_week,state_version")
        .eq("run_id", query.runId)
        .maybeSingle(),
      this.client
        .from("channel_rules")
        .select("channel_type_code")
        .eq("id", run.channel_rule_id)
        .eq("rule_set_id", run.rule_set_id)
        .maybeSingle(),
      run.specialty_code === null
        ? Promise.resolve({ data: null, error: null })
        : this.client
            .from("specialty_categories")
            .select("name")
            .eq("code", run.specialty_code)
            .maybeSingle(),
    ]);

    assertQuerySucceeded(stateResult.error, operation);
    assertQuerySucceeded(channelResult.error, operation);
    assertQuerySucceeded(specialtyResult.error, operation);
    if (
      !stateResult.data ||
      !channelResult.data ||
      (run.specialty_code !== null && !specialtyResult.data)
    ) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    return {
      status: "found",
      runStatus: run.status as GameRunStatus,
      currentWeek: stateResult.data.current_week,
      stateVersion: stateResult.data.state_version,
      channelType: channelResult.data.channel_type_code,
      specialty: specialtyResult.data?.name ?? null,
    };
  }

  async getCapacity(
    query: CreateIdeaCapacityQuery,
  ): Promise<CreateIdeaCapacity | null> {
    const operation = "createIdea.getCapacity";
    const { data: ownedRun, error: runError } = await this.client
      .from("game_runs")
      .select("rule_set_id")
      .eq("id", query.runId)
      .eq("user_id", query.actorUserId)
      .maybeSingle();

    assertQuerySucceeded(runError, operation);
    if (!ownedRun) {
      return null;
    }

    const [rulesResult, weeklyResult, stockResult, conditionResult] =
      await Promise.all([
        this.client
          .from("global_rules")
          .select("ideas_per_week,idea_stock_max")
          .eq("rule_set_id", ownedRun.rule_set_id)
          .maybeSingle(),
        this.client
          .from("player_ideas")
          .select("id", { count: "exact", head: true })
          .eq("run_id", query.runId)
          .eq("created_week", query.weekNumber),
        this.client
          .from("idea_stock_view")
          .select("idea_id", { count: "exact", head: true })
          .eq("run_id", query.runId),
        this.client
          .from("run_conditions")
          .select("id", { count: "exact", head: true })
          .eq("run_id", query.runId)
          .is("recovered_at", null)
          .lte("unavailable_from_week", query.weekNumber)
          .gte("unavailable_through_week", query.weekNumber),
      ]);

    assertQuerySucceeded(rulesResult.error, operation);
    assertQuerySucceeded(weeklyResult.error, operation);
    assertQuerySucceeded(stockResult.error, operation);
    assertQuerySucceeded(conditionResult.error, operation);
    if (
      !rulesResult.data ||
      weeklyResult.count === null ||
      stockResult.count === null ||
      conditionResult.count === null
    ) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    return {
      ideasCreatedThisWeek: weeklyResult.count,
      pendingIdeaCount: stockResult.count,
      ideasPerWeekLimit: rulesResult.data.ideas_per_week,
      ideaStockLimit: rulesResult.data.idea_stock_max,
      isActivityUnavailable: conditionResult.count > 0,
    };
  }

  async commitCreateIdea(command: CommitCreateIdeaCommand) {
    const { data, error } = await this.client.rpc("commit_create_idea", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_title: command.title,
      ...(command.description === null
        ? {}
        : { p_description: command.description }),
      p_expected_version: command.expectedVersion,
      p_score: command.evaluation.score,
      p_evaluation_status: command.evaluation.status,
      p_model: command.evaluation.model,
      p_prompt_version: command.evaluation.promptVersion,
    });

    if (error) {
      throw mapCreateIdeaRpcError(error.message);
    }
    if (typeof data !== "string" || data.length === 0) {
      throw new CommitCreateIdeaError("COMMIT_FAILED");
    }

    return { ideaId: data };
  }
}

type QueryError = { message: string } | null;

function assertQuerySucceeded(error: QueryError, operation: string): void {
  if (error) {
    throw new RepositoryError("QUERY_FAILED", operation);
  }
}

const createIdeaErrorCodes = new Map<
  string,
  CommitCreateIdeaError["code"]
>([
  ["CREATE_IDEA_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["CREATE_IDEA_FORBIDDEN", "FORBIDDEN"],
  ["CREATE_IDEA_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
  ["CREATE_IDEA_STALE_STATE", "STALE_STATE"],
  ["CREATE_IDEA_ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
  ["CREATE_IDEA_WEEKLY_LIMIT", "IDEA_WEEKLY_LIMIT"],
  ["CREATE_IDEA_STOCK_FULL", "IDEA_STOCK_FULL"],
  ["CREATE_IDEA_VALIDATION_ERROR", "VALIDATION_ERROR"],
]);

function mapCreateIdeaRpcError(message: string): CommitCreateIdeaError {
  return new CommitCreateIdeaError(
    createIdeaErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}
