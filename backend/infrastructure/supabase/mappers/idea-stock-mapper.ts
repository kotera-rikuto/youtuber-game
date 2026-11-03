import "server-only";

import type { IdeaQueue, PendingIdea } from "@/backend/domain/game/idea-stock";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import {
  parseDate,
  requirePositiveInteger,
  requireString,
} from "@/backend/infrastructure/supabase/mappers/validation";

type IdeaStockRow =
  Database["public"]["Views"]["idea_stock_view"]["Row"];

export function mapIdeaQueue(
  runId: string,
  rows: readonly IdeaStockRow[],
): IdeaQueue {
  const items = rows.map((row, index) => mapPendingIdea(runId, row, index + 1));
  return { runId, items };
}

function mapPendingIdea(
  runId: string,
  row: IdeaStockRow,
  expectedPosition: number,
): PendingIdea {
  if (row.run_id !== runId) {
    throw new DataIntegrityError("Idea stock row belongs to a different run.");
  }
  if (
    row.idea_source !== "player" ||
    row.stock_status !== "queued" ||
    row.is_pending !== true
  ) {
    throw new DataIntegrityError("Idea stock row is not a pending player idea.");
  }

  const position = requirePositiveInteger(row.position, "position");
  if (position !== expectedPosition) {
    throw new DataIntegrityError(
      "Idea queue positions must be contiguous and start at one.",
    );
  }

  return {
    id: requireString(row.idea_id, "idea_id"),
    position,
    title: requireString(row.title, "title"),
    description: row.description,
    createdWeek: requirePositiveInteger(row.created_week, "created_week"),
    createdAt: parseDate(row.created_at, "created_at"),
    queuedAt: parseDate(row.queued_at, "queued_at"),
  };
}
