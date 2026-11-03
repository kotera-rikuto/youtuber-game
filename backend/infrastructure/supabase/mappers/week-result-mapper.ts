import "server-only";

import type {
  DomainJson,
  WeekEvent,
  WeekResult,
} from "@/backend/domain/game/week-result";
import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import {
  parseDate,
  requireArray,
  requireBoolean,
  requireGameRunStatus,
  requireInteger,
  requireNonnegativeInteger,
  requirePositiveInteger,
  requireRecord,
  requireString,
} from "@/backend/infrastructure/supabase/mappers/validation";

type WeekHistoryRow =
  Database["public"]["Views"]["week_history_view"]["Row"];

export function mapWeekResult(row: WeekHistoryRow): WeekResult {
  return {
    id: requireString(row.week_result_id, "week_result_id"),
    runId: requireString(row.run_id, "run_id"),
    weekNumber: requirePositiveInteger(row.week_number, "week_number"),
    stageNumber:
      row.stage_number === null
        ? null
        : requirePositiveInteger(row.stage_number, "stage_number"),
    action: mapAction(row.action_code, row.action_name),
    plannedVideoCount:
      row.planned_video_count === null
        ? null
        : requirePositiveInteger(
            row.planned_video_count,
            "planned_video_count",
          ),
    postedVideoCount: requireNonnegativeInteger(
      row.posted_video_count,
      "posted_video_count",
    ),
    viewsBeforeEvent: requireNonnegativeInteger(
      row.views_before_event,
      "views_before_event",
    ),
    finalViews: requireNonnegativeInteger(row.final_views, "final_views"),
    eventViewChange: requireInteger(
      row.event_view_change,
      "event_view_change",
    ),
    subscribersBefore: requireNonnegativeInteger(
      row.subscribers_before,
      "subscribers_before",
    ),
    maxSubscribersDuringWeek: requireNonnegativeInteger(
      row.max_subscribers_during_week,
      "max_subscribers_during_week",
    ),
    subscribersAfter: requireNonnegativeInteger(
      row.subscribers_after,
      "subscribers_after",
    ),
    subscriberChange: requireInteger(
      row.subscriber_change,
      "subscriber_change",
    ),
    energyBefore: requireNonnegativeInteger(
      row.energy_before,
      "energy_before",
    ),
    energyAfter: requireNonnegativeInteger(row.energy_after, "energy_after"),
    energyChange: requireInteger(row.energy_change, "energy_change"),
    cashBefore: requireNonnegativeInteger(row.cash_before, "cash_before"),
    cashAfter: requireNonnegativeInteger(row.cash_after, "cash_after"),
    cashChange: requireInteger(row.cash_change, "cash_change"),
    adRevenue: requireNonnegativeInteger(row.ad_revenue, "ad_revenue"),
    flameCountBefore: requireNonnegativeInteger(
      row.flame_count_before,
      "flame_count_before",
    ),
    flameCountAfter: requireNonnegativeInteger(
      row.flame_count_after,
      "flame_count_after",
    ),
    flameCountChange: requireInteger(
      row.flame_count_change,
      "flame_count_change",
    ),
    hadFlame: requireBoolean(row.had_flame, "had_flame"),
    healthCondition: mapHealthCondition(row),
    wasActivityUnavailable: requireBoolean(
      row.was_activity_unavailable,
      "was_activity_unavailable",
    ),
    runStatusAfter: requireGameRunStatus(
      row.run_status_after,
      "run_status_after",
    ),
    stateVersionAfter: requireNonnegativeInteger(
      row.state_version_after,
      "state_version_after",
    ),
    createdAt: parseDate(row.created_at, "created_at"),
    events: mapEvents(row.events),
  };
}

function mapAction(
  code: string | null,
  name: string | null,
): WeekResult["action"] {
  if (code === null && name === null) {
    return null;
  }
  if (code === null || name === null) {
    throw new DataIntegrityError("Action code and name must be present together.");
  }

  return {
    code: requireString(code, "action_code"),
    name: requireString(name, "action_name"),
  };
}

function mapHealthCondition(row: WeekHistoryRow): WeekResult["healthCondition"] {
  if (row.health_condition_started === false) {
    if (
      row.health_condition_duration_weeks !== null ||
      row.unavailable_from_week !== null ||
      row.unavailable_through_week !== null
    ) {
      throw new DataIntegrityError(
        "Health condition details cannot exist without a start.",
      );
    }
    return null;
  }
  if (row.health_condition_started !== true) {
    throw new DataIntegrityError("health_condition_started must be a boolean.");
  }

  return {
    durationWeeks: requireNonnegativeInteger(
      row.health_condition_duration_weeks,
      "health_condition_duration_weeks",
    ),
    unavailableFromWeek: requirePositiveInteger(
      row.unavailable_from_week,
      "unavailable_from_week",
    ),
    unavailableThroughWeek: requirePositiveInteger(
      row.unavailable_through_week,
      "unavailable_through_week",
    ),
  };
}

function mapEvents(value: WeekHistoryRow["events"]): readonly WeekEvent[] {
  return requireArray(value, "events").map((item, index) => {
    const event = requireRecord(item, `events[${index}]`);
    return {
      code: requireString(event.code, `events[${index}].code`),
      name: requireString(event.name, `events[${index}].name`),
      sequenceNumber: requirePositiveInteger(
        event.sequenceNumber,
        `events[${index}].sequenceNumber`,
      ),
      displayMetadata: mapDomainJson(
        event.displayMetadata,
        `events[${index}].displayMetadata`,
      ),
    };
  });
}

function mapDomainJson(value: unknown, fieldName: string): DomainJson {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    return value;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new DataIntegrityError(`${fieldName} contains a non-finite number.`);
    }
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((entry, index) =>
      mapDomainJson(entry, `${fieldName}[${index}]`),
    );
  }
  if (typeof value === "object" && value !== null) {
    const mapped: Record<string, DomainJson> = {};
    for (const [key, entry] of Object.entries(value)) {
      if (entry === undefined) {
        throw new DataIntegrityError(`${fieldName}.${key} must be valid JSON.`);
      }
      mapped[key] = mapDomainJson(entry, `${fieldName}.${key}`);
    }
    return mapped;
  }

  throw new DataIntegrityError(`${fieldName} must be valid JSON.`);
}
