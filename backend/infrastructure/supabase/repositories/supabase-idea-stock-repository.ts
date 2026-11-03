import "server-only";

import type {
  IdeasCreatedInWeekQuery,
  IdeaStockRepository,
} from "@/backend/application/ports/idea-stock-repository";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import type { IdeaQueue } from "@/backend/domain/game/idea-stock";
import { mapIdeaQueue } from "@/backend/infrastructure/supabase/mappers/idea-stock-mapper";
import {
  type DatabaseClient,
  findOwnedRun,
  mapRepositoryData,
} from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseIdeaStockRepository implements IdeaStockRepository {
  constructor(private readonly client: DatabaseClient) {}

  async getPendingQueue(query: OwnedRunQuery): Promise<IdeaQueue | null> {
    const operation = "ideaStock.getPendingQueue";
    if (!(await this.isOwned(query, operation))) {
      return null;
    }

    const { data, error } = await this.client
      .from("idea_stock_view")
      .select(
        "run_id,idea_id,idea_source,position,title,description,created_week,created_at,queued_at,stock_status,is_pending",
      )
      .eq("run_id", query.runId)
      .order("position", { ascending: true });

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () => mapIdeaQueue(query.runId, data));
  }

  async countPending(query: OwnedRunQuery): Promise<number | null> {
    const operation = "ideaStock.countPending";
    if (!(await this.isOwned(query, operation))) {
      return null;
    }

    const { count, error } = await this.client
      .from("idea_stock_view")
      .select("idea_id", { count: "exact", head: true })
      .eq("run_id", query.runId);

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (count === null) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    return count;
  }

  async countCreatedInWeek(
    query: IdeasCreatedInWeekQuery,
  ): Promise<number | null> {
    const operation = "ideaStock.countCreatedInWeek";
    if (!(await this.isOwned(query, operation))) {
      return null;
    }

    const { count, error } = await this.client
      .from("player_ideas")
      .select("id", { count: "exact", head: true })
      .eq("run_id", query.runId)
      .eq("created_week", query.weekNumber);

    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (count === null) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    return count;
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
