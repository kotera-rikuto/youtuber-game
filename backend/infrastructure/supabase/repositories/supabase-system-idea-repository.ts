import "server-only";

import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import {
  CommitSystemIdeaCycleError,
  type CommitSystemIdeaCycleCommand,
  type SystemIdeaRepository,
} from "@/backend/application/ports/system-idea-repository";
import type {
  SystemIdeaCycle,
  SystemIdeaPoolCandidate,
} from "@/backend/domain/game/system-idea-cycle";
import {
  mapSystemIdeaCycles,
  mapSystemIdeaPool,
} from "@/backend/infrastructure/supabase/mappers/system-idea-mapper";
import {
  type DatabaseClient,
  findOwnedRun,
  mapRepositoryData,
} from "@/backend/infrastructure/supabase/repositories/repository-support";

export class SupabaseSystemIdeaRepository implements SystemIdeaRepository {
  constructor(private readonly client: DatabaseClient) {}

  async findPool(
    query: OwnedRunQuery,
  ): Promise<readonly SystemIdeaPoolCandidate[] | null> {
    const operation = "systemIdea.findPool";
    const ownedRun = await findOwnedRun(
      this.client,
      query.actorUserId,
      query.runId,
      operation,
    );
    if (!ownedRun) {
      return null;
    }

    const { data: game, error: gameError } = await this.client
      .from("current_game_view")
      .select("channel_type_code,specialty_code")
      .eq("run_id", query.runId)
      .maybeSingle();
    if (gameError) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (!game?.channel_type_code) {
      throw new RepositoryError("INVALID_DATA", operation);
    }

    let poolQuery = this.client
      .from("rule_set_system_ideas")
      .select(
        "id,system_idea_template_id,system_idea_templates!inner(id,title,channel_type_code,specialty_code,enabled)",
      )
      .eq("rule_set_id", ownedRun.rule_set_id)
      .eq("enabled", true)
      .eq("system_idea_templates.enabled", true)
      .eq("system_idea_templates.channel_type_code", game.channel_type_code);

    poolQuery = game.specialty_code
      ? poolQuery.eq("system_idea_templates.specialty_code", game.specialty_code)
      : poolQuery.is("system_idea_templates.specialty_code", null);

    const { data, error } = await poolQuery.order("id", { ascending: true });
    if (error) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () => mapSystemIdeaPool(data));
  }

  async listCycles(
    query: OwnedRunQuery,
  ): Promise<readonly SystemIdeaCycle[] | null> {
    const operation = "systemIdea.listCycles";
    if (
      !(await findOwnedRun(
        this.client,
        query.actorUserId,
        query.runId,
        operation,
      ))
    ) {
      return null;
    }

    const { data: cycleRows, error: cycleError } = await this.client
      .from("system_idea_cycles")
      .select("id,cycle_number")
      .eq("run_id", query.runId)
      .order("cycle_number", { ascending: false })
      // The commit RPC can pre-create only one successor, so at most the latest
      // two cycles can contain entries needed by one (maximum seven-post) week.
      .limit(2);
    if (cycleError) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }
    if (cycleRows.length === 0) {
      return [];
    }

    const cycleIds = cycleRows.map((cycle) => cycle.id);
    const { data: entryRows, error: entryError } = await this.client
      .from("system_idea_cycle_entries")
      .select("id,cycle_id,rule_set_system_idea_id,position")
      .in("cycle_id", cycleIds)
      .order("position", { ascending: true });
    if (entryError) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    const associationIds = entryRows.map(
      (entry) => entry.rule_set_system_idea_id,
    );
    const { data: associationRows, error: associationError } = await this.client
      .from("rule_set_system_ideas")
      .select("id,system_idea_template_id")
      .in("id", associationIds);
    if (associationError) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    const templateIds = associationRows.map(
      (association) => association.system_idea_template_id,
    );
    const { data: templateRows, error: templateError } = await this.client
      .from("system_idea_templates")
      .select("id,title")
      .in("id", templateIds);
    if (templateError) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    const { data: videoRows, error: videoError } = await this.client
      .from("videos")
      .select(
        "system_idea_cycle_entry_id,system_idea_cycle_entries!inner(cycle_id)",
      )
      .in("system_idea_cycle_entries.cycle_id", cycleIds)
      .not("system_idea_cycle_entry_id", "is", null);
    if (videoError) {
      throw new RepositoryError("QUERY_FAILED", operation);
    }

    return mapRepositoryData(operation, () =>
      mapSystemIdeaCycles(
        [...cycleRows].sort(
          (left, right) => left.cycle_number - right.cycle_number,
        ),
        entryRows,
        associationRows,
        templateRows,
        new Set(
          videoRows.flatMap((video) =>
            video.system_idea_cycle_entry_id
              ? [video.system_idea_cycle_entry_id]
              : [],
          ),
        ),
      ),
    );
  }

  async commitCycle(
    command: CommitSystemIdeaCycleCommand,
  ): Promise<{ cycleId: string }> {
    const { data, error } = await this.client.rpc("commit_system_idea_cycle", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_required_count: command.requiredCount,
      p_ordered_rule_set_system_idea_ids: [
        ...command.orderedRuleSetSystemIdeaIds,
      ],
    });

    if (error) {
      throw mapCommitCycleRpcError(error.code, error.message);
    }
    if (typeof data !== "string" || data.length === 0) {
      throw new CommitSystemIdeaCycleError("COMMIT_FAILED");
    }

    return { cycleId: data };
  }
}

const commitErrorCodes = new Map<string, CommitSystemIdeaCycleError["code"]>([
  ["SYSTEM_IDEA_CYCLE_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
  ["SYSTEM_IDEA_CYCLE_POOL_INVALID", "POOL_INVALID"],
  ["SYSTEM_IDEA_CYCLE_VALIDATION_ERROR", "POOL_INVALID"],
  ["SYSTEM_IDEA_CYCLE_STATE_INVALID", "CYCLE_CONFLICT"],
  ["SYSTEM_IDEA_CYCLE_BOUNDARY_CONFLICT", "CYCLE_CONFLICT"],
]);

function mapCommitCycleRpcError(code: string, message: string) {
  if (code === "23505") {
    return new CommitSystemIdeaCycleError("CYCLE_CONFLICT");
  }
  return new CommitSystemIdeaCycleError(
    commitErrorCodes.get(message) ?? "COMMIT_FAILED",
  );
}
