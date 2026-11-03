import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { WeekResult } from "@/backend/domain/game/week-result";

export type CommittedWeekQuery = OwnedRunQuery & {
  weekNumber: number;
};

export type IdempotentWeekResultQuery = OwnedRunQuery & {
  idempotencyKey: string;
};

export interface WeekResultRepository {
  findCommittedWeek(query: CommittedWeekQuery): Promise<WeekResult | null>;
  findByIdempotencyKey(
    query: IdempotentWeekResultQuery,
  ): Promise<WeekResult | null>;
  listHistory(query: OwnedRunQuery): Promise<readonly WeekResult[] | null>;
}
