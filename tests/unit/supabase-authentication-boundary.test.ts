import { AuthSessionMissingError } from "@supabase/supabase-js";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/server", () => ({
  createWritableClient: vi.fn(),
}));

import {
  establishAnonymousSessionForGameStart,
  getAuthenticatedUseCaseContext,
} from "@/backend/infrastructure/supabase/authentication";
import { createWritableClient } from "@/lib/supabase/server";
import { supabaseAuthCookieOptions } from "@/lib/supabase/server-config";

function useFakeSupabaseAuth(auth: {
  getUser: ReturnType<typeof vi.fn>;
  signInAnonymously: ReturnType<typeof vi.fn>;
}) {
  vi.mocked(createWritableClient).mockResolvedValue({ auth } as never);
}

describe("Supabase authentication boundary", () => {
  beforeEach(() => {
    vi.mocked(createWritableClient).mockReset();
  });

  it("does not accept public input such as userId", () => {
    expect(establishAnonymousSessionForGameStart).toHaveLength(0);
  });

  it("configures the Supabase session cookie as HttpOnly", () => {
    expect(supabaseAuthCookieOptions).toMatchObject({
      httpOnly: true,
      path: "/",
      sameSite: "lax",
    });
  });

  it("signs in and verifies the Supabase user when no session exists", async () => {
    const getUser = vi
      .fn()
      .mockResolvedValueOnce({
        data: { user: null },
        error: new AuthSessionMissingError(),
      })
      .mockResolvedValueOnce({
        data: { user: { id: "created-user-id" } },
        error: null,
      });
    const signInAnonymously = vi.fn().mockResolvedValue({
      data: {
        user: { id: "created-user-id" },
        session: { access_token: "not-logged" },
      },
      error: null,
    });
    useFakeSupabaseAuth({ getUser, signInAnonymously });

    await expect(establishAnonymousSessionForGameStart()).resolves.toEqual({
      actorUserId: "created-user-id",
    });
    expect(signInAnonymously).toHaveBeenCalledOnce();
    expect(getUser).toHaveBeenCalledTimes(2);
  });

  it("does not create a second user when Supabase verifies the session", async () => {
    const getUser = vi.fn().mockResolvedValue({
      data: { user: { id: "existing-user-id" } },
      error: null,
    });
    const signInAnonymously = vi.fn();
    useFakeSupabaseAuth({ getUser, signInAnonymously });

    await expect(establishAnonymousSessionForGameStart()).resolves.toEqual({
      actorUserId: "existing-user-id",
    });
    expect(signInAnonymously).not.toHaveBeenCalled();
  });

  it("does not authenticate or leak provider details after an API failure", async () => {
    const providerSecret = "provider-error-with-refresh-token";
    const getUser = vi.fn().mockResolvedValue({
      data: { user: null },
      error: new Error(providerSecret),
    });
    const signInAnonymously = vi.fn();
    useFakeSupabaseAuth({ getUser, signInAnonymously });

    let thrownError: unknown;
    try {
      await getAuthenticatedUseCaseContext();
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError).toMatchObject({
      name: "AuthenticationError",
      code: "UNAUTHENTICATED",
    });
    expect((thrownError as Error).message).not.toContain(providerSecret);
    expect(signInAnonymously).not.toHaveBeenCalled();
  });
});
