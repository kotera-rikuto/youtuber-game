import "server-only";

import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import type {
  CommittedWeekQuery,
  IdempotentWeekResultQuery,
  WeekResultRepository,
} from "@/backend/application/ports/week-result-repository";
import type { WeekResult } from "@/backend/domain/game/week-result";
import { mapWeekResult } from "@/backend/infrastructure/supabase/mappers/week-result-mapper";
import {
  type DatabaseClient,
  findOwnedRun,
  mapRepositoryData,
} from "@/backend/infrastructure/supabase/repositories/repository-support";

const weekHistoryColumns =
  "run_id,week_result_id,week_number,stage_number,action_code,action_name,planned_video_count,posted_video_count,views_before_event,final_views,event_view_change,subscribers_before,max_subscribers_during_week,subscribers_after,subscriber_change,energy_before,energy_after,energy_change,cash_before,cash_after,cash_change,ad_revenue,flame_count_before,flame_count_after,flame_count_change,had_flame,health_condition_started,health_condition_duration_weeks,unavailable_from_week,unavailable_through_week,was_activity_unavailable,run_status_after,state_version_after,created_at,events";

export class SupabaseWeekResultRepository implements WeekResultRepository {
  constructor(private readonly client: DatabaseClient) {}

  async findCommittedWeek(
    query: CommittedWeekQuery,
  ): Promise<WeekResult | null> {
    const operation = "weekResult.findCommittedWeek";
    if (!(await this.isOwned(query, operation))) {
      return null;
    }

    return this.findHistoryRow(query.runId, query.weekNumber, operation);
  }

  async findByIdempotencyKey(
    query: IdempotentWeekResultQuery,
  ): Promise<WeekResult | null> {
    const operation = "weekResult.findByIdempotencyKey";
    if (!(await this.isOwned(query, operation))) {
      return null;
    }

    const { data, error } = await this.client
      .from("week_results")
      .select("run_id,week_number")
      .eq("run_id", query.runId)
      .eq("execution_id", query.idempotencyKey)
      .maybeSingle();

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (!data) {
      return null;
    }

    return this.findHistoryRow(data.run_id, data.week_number, operation);
  }

  async listHistory(
    query: OwnedRunQuery,
  ): Promise<readonly WeekResult[] | null> {
    const operation = "weekResult.listHistory";
    if (!(await this.isOwned(query, operation))) {
      return null;
    }

    const { data, error } = await this.client
      .from("week_history_view")
      .select(weekHistoryColumns)
      .eq("run_id", query.runId)
      .order("week_number", { ascending: true });

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () => data.map(mapWeekResult));
  }

  private async findHistoryRow(
    runId: string,
    weekNumber: number,
    operation: string,
  ): Promise<WeekResult | null> {
    const { data, error } = await this.client
      .from("week_history_view")
      .select(weekHistoryColumns)
      .eq("run_id", runId)
      .eq("week_number", weekNumber)
      .maybeSingle();

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return data
      ? mapRepositoryData(operation, () => mapWeekResult(data))
      : null;
  }

  private async isOwned(query: OwnedRunQuery, operation: string) {
    return Boolean(
      await findOwnedRun(
        this.client,
        query.actorUserId,
        query.runId,
        operation,
      ),
    );
  }
}
