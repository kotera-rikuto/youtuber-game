import "server-only";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { GameRunRepository } from "@/backend/application/ports/game-run-repository";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import type { GameRun } from "@/backend/domain/game/game-run";
import {
  mapCurrentGame,
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
