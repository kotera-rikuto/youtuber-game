import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  AdvanceWeekCommitError,
  type FatalAdvanceWeekCommitCommand,
} from "@/backend/application/ports/advance-week-commit-repository";
import type { Json } from "@/backend/infrastructure/supabase/database.types";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { SupabaseAdvanceWeekCommitRepository } from "@/backend/infrastructure/supabase/repositories/supabase-advance-week-commit-repository";

vi.mock("server-only", () => ({}));

const command: FatalAdvanceWeekCommitCommand = {
  kind: "fatal_game_over",
  actorUserId:
    "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"],
  runId: "00000000-0000-4000-8000-000000000002",
  attemptedWeek: 3,
  expectedVersion: 2,
  idempotencyKey: "00000000-0000-4000-8000-000000000003",
  reason: "death",
  calculatedEnergy: 0,
  calculatedFlameCount: 1,
};

describe("SupabaseAdvanceWeekCommitRepository", () => {
  it("commits through exactly one RPC call and maps the receipt", async () => {
    const receipt: Json = {
      outcome: "fatal_game_over",
      runId: command.runId,
      attemptedWeek: command.attemptedWeek,
      terminationId: "00000000-0000-4000-8000-000000000004",
      reason: "death",
      runStatusAfter: "game_over",
    };
    const rpc = vi.fn().mockResolvedValue({ data: receipt, error: null });
    const repository = new SupabaseAdvanceWeekCommitRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.commitAdvanceWeek(command)).resolves.toEqual(receipt);
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("commit_advance_week", {
      p_command: command,
    });
  });

  it.each([
    ["ADVANCE_WEEK_STALE_STATE", "STALE_STATE"],
    ["ADVANCE_WEEK_IDEMPOTENCY_KEY_REUSED", "IDEMPOTENCY_KEY_REUSED"],
    ["ADVANCE_WEEK_VALIDATION_ERROR", "VALIDATION_ERROR"],
  ] as const)("maps %s into the stable %s error", async (message, code) => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: "P0001", message },
    });
    const repository = new SupabaseAdvanceWeekCommitRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.commitAdvanceWeek(command)).rejects.toMatchObject({
      name: "AdvanceWeekCommitError",
      code,
    } satisfies Partial<AdvanceWeekCommitError>);
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it("rejects a malformed successful response", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { outcome: "fatal_game_over" },
      error: null,
    });
    const repository = new SupabaseAdvanceWeekCommitRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.commitAdvanceWeek(command)).rejects.toMatchObject({
      name: "AdvanceWeekCommitError",
      code: "COMMIT_FAILED",
    } satisfies Partial<AdvanceWeekCommitError>);
  });
});
