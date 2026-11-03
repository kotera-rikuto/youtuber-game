import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { AllocateAbilityPointsCommand } from "@/backend/application/ports/ability-allocation-repository";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { SupabaseAbilityAllocationRepository } from "@/backend/infrastructure/supabase/repositories/supabase-ability-allocation-repository";

vi.mock("server-only", () => ({}));

const command: AllocateAbilityPointsCommand = {
  actorUserId:
    "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"],
  runId: "00000000-0000-4000-8000-000000000002",
  allocations: {
    planning: 1,
    talking: 2,
    expertise: 3,
    editing: 4,
    visual: 5,
    filming: 6,
  },
  expectedVersion: 4,
};

describe("SupabaseAbilityAllocationRepository", () => {
  it("commits through one RPC call and maps the next state version", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: 5, error: null });
    const repository = new SupabaseAbilityAllocationRepository(
      { rpc } as unknown as DatabaseClient,
    );

    await expect(repository.allocateAbilityPoints(command)).resolves.toEqual({
      nextStateVersion: 5,
    });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith("allocate_ability_points", {
      p_actor_user_id: command.actorUserId,
      p_run_id: command.runId,
      p_allocations: command.allocations,
      p_expected_version: command.expectedVersion,
    });
  });

  it.each([
    ["ALLOCATE_ABILITY_POINTS_RUN_NOT_FOUND", "RUN_NOT_FOUND"],
    ["ALLOCATE_ABILITY_POINTS_FORBIDDEN", "FORBIDDEN"],
    ["ALLOCATE_ABILITY_POINTS_RUN_NOT_PLAYABLE", "RUN_NOT_PLAYABLE"],
    ["ALLOCATE_ABILITY_POINTS_ACTIVITY_UNAVAILABLE", "ACTIVITY_UNAVAILABLE"],
    ["ALLOCATE_ABILITY_POINTS_STALE_STATE", "STALE_STATE"],
    ["ALLOCATE_ABILITY_POINTS_INVALID_ALLOCATION", "INVALID_ALLOCATION"],
    [
      "ALLOCATE_ABILITY_POINTS_INSUFFICIENT_ABILITY_POINTS",
      "INSUFFICIENT_ABILITY_POINTS",
    ],
    [
      "ALLOCATE_ABILITY_POINTS_ABILITY_LIMIT_EXCEEDED",
      "ABILITY_LIMIT_EXCEEDED",
    ],
  ] as const)("maps %s to %s", async (message, expectedCode) => {
    const repository = repositoryWithError("P0001", message);

    await expect(repository.allocateAbilityPoints(command)).rejects.toMatchObject({
      code: expectedCode,
    });
  });

  it.each(["23514", "23503", "22P02"])(
    "maps PostgreSQL input error %s to INVALID_ALLOCATION",
    async (code) => {
      const repository = repositoryWithError(code, "database constraint");

      await expect(repository.allocateAbilityPoints(command)).rejects.toMatchObject({
        code: "INVALID_ALLOCATION",
      });
    },
  );

  it("maps an unknown database failure to COMMIT_FAILED", async () => {
    const repository = repositoryWithError("XX000", "unexpected");

    await expect(repository.allocateAbilityPoints(command)).rejects.toMatchObject({
      code: "COMMIT_FAILED",
    });
  });

  it.each([null, 4, 6, 5.5, "5"])(
    "rejects malformed successful response %j",
    async (data) => {
      const rpc = vi.fn().mockResolvedValue({ data, error: null });
      const repository = new SupabaseAbilityAllocationRepository(
        { rpc } as unknown as DatabaseClient,
      );

      await expect(repository.allocateAbilityPoints(command)).rejects.toMatchObject({
        code: "COMMIT_FAILED",
      });
    },
  );
});

function repositoryWithError(code: string, message: string) {
  const rpc = vi.fn().mockResolvedValue({ data: null, error: { code, message } });
  return new SupabaseAbilityAllocationRepository(
    { rpc } as unknown as DatabaseClient,
  );
}
