import "server-only";

import {
  isAuthSessionMissingError,
  type SupabaseClient,
} from "@supabase/supabase-js";

import {
  ensureAnonymousUserForGameStart,
  requireUseCaseContext,
  type AnonymousAuthenticationGateway,
  type UseCaseContext,
  type VerifiedUserLookup,
} from "@/backend/application/auth/authentication";
import { createWritableClient } from "@/lib/supabase/server";

type SupabaseAuthClient = Pick<
  SupabaseClient["auth"],
  "getUser" | "signInAnonymously"
>;

class SupabaseAuthenticationGateway
  implements AnonymousAuthenticationGateway
{
  constructor(private readonly auth: SupabaseAuthClient) {}

  async getVerifiedUser(): Promise<VerifiedUserLookup> {
    try {
      const { data, error } = await this.auth.getUser();

      if (error) {
        return isAuthSessionMissingError(error)
          ? { status: "unauthenticated" }
          : { status: "failed" };
      }

      return data.user
        ? { status: "authenticated", userId: data.user.id }
        : { status: "unauthenticated" };
    } catch {
      return { status: "failed" };
    }
  }

  async signInAnonymously(): Promise<"signed-in" | "failed"> {
    try {
      const { data, error } = await this.auth.signInAnonymously();

      return !error && data.user && data.session ? "signed-in" : "failed";
    } catch {
      return "failed";
    }
  }
}

export async function establishAnonymousSessionForGameStart(): Promise<UseCaseContext> {
  const client = await createWritableClient();
  const authentication = new SupabaseAuthenticationGateway(client.auth);

  return ensureAnonymousUserForGameStart(authentication);
}

export async function getAuthenticatedUseCaseContext(): Promise<UseCaseContext> {
  const client = await createWritableClient();
  const authentication = new SupabaseAuthenticationGateway(client.auth);

  return requireUseCaseContext(authentication);
}
