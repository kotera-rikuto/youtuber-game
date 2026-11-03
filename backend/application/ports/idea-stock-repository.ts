import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { IdeaQueue } from "@/backend/domain/game/idea-stock";

export type IdeasCreatedInWeekQuery = OwnedRunQuery & {
  weekNumber: number;
};

export interface IdeaStockRepository {
  getPendingQueue(query: OwnedRunQuery): Promise<IdeaQueue | null>;
  countPending(query: OwnedRunQuery): Promise<number | null>;
  countCreatedInWeek(
    query: IdeasCreatedInWeekQuery,
  ): Promise<number | null>;
}
