import { describe, expect, it, vi } from "vitest";

import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { DatabaseClient } from "@/backend/infrastructure/supabase/repositories/repository-support";
import { SupabaseGameRunManagementRepository } from "@/backend/infrastructure/supabase/repositories/supabase-game-run-management-repository";

vi.mock("server-only", () => ({}));

const actorUserId = "00000000-0000-4000-8000-000000000001" as UseCaseContext["actorUserId"];

describe("SupabaseGameRunManagementRepository", () => {
  it("commits abandonGame through one RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { occurredWeek: 7 }, error: null });
    const repository = new SupabaseGameRunManagementRepository({ rpc } as unknown as DatabaseClient);

    await expect(repository.abandonGame({ actorUserId, runId: "run-1", expectedVersion: 3 })).resolves.toEqual({
      occurredWeek: 7,
    });
    expect(rpc).toHaveBeenCalledWith("abandon_game", {
      p_actor_user_id: actorUserId,
      p_run_id: "run-1",
      p_expected_version: 3,
    });
  });

  it("commits renameChannel through one RPC", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { channelName: "変更後", nextStateVersion: 4 },
      error: null,
    });
    const repository = new SupabaseGameRunManagementRepository({ rpc } as unknown as DatabaseClient);

    await expect(
      repository.renameChannel({
        actorUserId,
        runId: "run-1",
        channelName: "変更後",
        expectedVersion: 3,
      }),
    ).resolves.toEqual({ channelName: "変更後", nextStateVersion: 4 });
  });

  it.each([
    "RUN_NOT_FOUND",
    "FORBIDDEN",
    "RUN_NOT_ACTIVE",
    "STALE_STATE",
    "INVALID_CHANNEL_NAME",
    "ALREADY_ABANDONED",
  ] as const)("maps the stable error %s", async (code) => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: "P0001", message: `ABANDON_GAME_${code}` },
    });
    const repository = new SupabaseGameRunManagementRepository({ rpc } as unknown as DatabaseClient);

    await expect(repository.abandonGame({ actorUserId, runId: "run-1", expectedVersion: 0 })).rejects.toMatchObject({
      code,
    });
  });

  it("maps unknown errors and malformed receipts to COMMIT_FAILED", async () => {
    const unknownError = vi.fn().mockResolvedValue({
      data: null,
      error: { code: "XX000", message: "unexpected" },
    });
    const malformedReceipt = vi.fn().mockResolvedValue({ data: {}, error: null });

    await expect(
      new SupabaseGameRunManagementRepository({ rpc: unknownError } as unknown as DatabaseClient).abandonGame({
        actorUserId,
        runId: "run-1",
        expectedVersion: 0,
      }),
    ).rejects.toMatchObject({ code: "COMMIT_FAILED" });
    await expect(
      new SupabaseGameRunManagementRepository({ rpc: malformedReceipt } as unknown as DatabaseClient).abandonGame({
        actorUserId,
        runId: "run-1",
        expectedVersion: 0,
      }),
    ).rejects.toMatchObject({ code: "COMMIT_FAILED" });
  });
});