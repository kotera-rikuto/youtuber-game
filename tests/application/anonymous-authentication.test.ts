import {
  AuthenticationError,
  ensureAnonymousUserForGameStart,
  requireUseCaseContext,
  type AnonymousAuthenticationGateway,
  type VerifiedUserLookup,
} from "@/backend/application/auth/authentication";
import { describe, expect, it, vi } from "vitest";

function createAuthenticationGateway(
  verifiedUsers: VerifiedUserLookup[],
  signInStatus: "signed-in" | "failed" = "signed-in",
) {
  const getVerifiedUser = vi.fn(async () => {
    const verifiedUser = verifiedUsers.shift();

    if (!verifiedUser) {
      throw new Error("Fake authentication response is missing.");
    }

    return verifiedUser;
  });
  const signInAnonymously = vi.fn(async () => signInStatus);

  const gateway: AnonymousAuthenticationGateway = {
    getVerifiedUser,
    signInAnonymously,
  };

  return { gateway, getVerifiedUser, signInAnonymously };
}

describe("anonymous authentication", () => {
  it("signs in anonymously only when game start has no session", async () => {
    const authentication = createAuthenticationGateway([
      { status: "unauthenticated" },
      { status: "authenticated", userId: "created-user-id" },
    ]);

    await expect(
      ensureAnonymousUserForGameStart(authentication.gateway),
    ).resolves.toEqual({ actorUserId: "created-user-id" });
    expect(authentication.signInAnonymously).toHaveBeenCalledOnce();
    expect(authentication.getVerifiedUser).toHaveBeenCalledTimes(2);
  });

  it("reuses a verified existing user without creating another user", async () => {
    const authentication = createAuthenticationGateway([
      { status: "authenticated", userId: "existing-user-id" },
    ]);

    await expect(
      ensureAnonymousUserForGameStart(authentication.gateway),
    ).resolves.toEqual({ actorUserId: "existing-user-id" });
    expect(authentication.signInAnonymously).not.toHaveBeenCalled();
  });

  it("creates actorUserId from a verified user", async () => {
    const authentication = createAuthenticationGateway([
      { status: "authenticated", userId: "verified-user-id" },
    ]);

    await expect(requireUseCaseContext(authentication.gateway)).resolves.toEqual(
      { actorUserId: "verified-user-id" },
    );
  });

  it("rejects an unauthenticated context", async () => {
    const authentication = createAuthenticationGateway([
      { status: "unauthenticated" },
    ]);

    await expect(requireUseCaseContext(authentication.gateway)).rejects.toMatchObject(
      {
        name: "AuthenticationError",
        code: "UNAUTHENTICATED",
      },
    );
  });

  it("does not create or accept a user when verification API fails", async () => {
    const authentication = createAuthenticationGateway([{ status: "failed" }]);

    await expect(
      ensureAnonymousUserForGameStart(authentication.gateway),
    ).rejects.toBeInstanceOf(AuthenticationError);
    expect(authentication.signInAnonymously).not.toHaveBeenCalled();
  });

  it("does not expose provider details in authentication errors", async () => {
    const secretProviderDetail = "refresh-token-secret";
    const authentication = createAuthenticationGateway(
      [{ status: "unauthenticated" }],
      "failed",
    );

    let thrownError: unknown;
    try {
      await ensureAnonymousUserForGameStart(authentication.gateway);
    } catch (error) {
      thrownError = error;
    }

    expect(thrownError).toBeInstanceOf(AuthenticationError);
    expect((thrownError as Error).message).not.toContain(secretProviderDetail);
  });
});
