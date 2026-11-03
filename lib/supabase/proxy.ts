import "server-only";

import { createServerClient, type CookieMethodsServer } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import {
  getSupabasePublicConfig,
  supabaseAuthCookieOptions,
} from "@/lib/supabase/server-config";

type SessionRefreshClient = {
  auth: {
    getUser(): Promise<unknown>;
  };
};

type SessionRefreshClientFactory = (
  cookies: CookieMethodsServer,
) => SessionRefreshClient;

export async function updateSupabaseSession(
  request: NextRequest,
  createClient: SessionRefreshClientFactory = createSessionRefreshClient,
): Promise<NextResponse> {
  let response = NextResponse.next({ request });
  const responseHeaders = new Headers();

  const client = createClient({
    getAll: () => request.cookies.getAll(),
    setAll(cookiesToSet, headers) {
      for (const { name, value } of cookiesToSet) {
        request.cookies.set(name, value);
      }

      for (const [name, value] of Object.entries(headers)) {
        responseHeaders.set(name, value);
      }

      response = NextResponse.next({ request });

      for (const { name, value, options } of cookiesToSet) {
        response.cookies.set(name, value, options);
      }

      responseHeaders.forEach((value, name) => {
        response.headers.set(name, value);
      });
    },
  });

  await client.auth.getUser();

  return response;
}

function createSessionRefreshClient(
  cookieMethods: CookieMethodsServer,
): SessionRefreshClient {
  const { url, publishableKey } = getSupabasePublicConfig();

  return createServerClient(url, publishableKey, {
    cookieOptions: supabaseAuthCookieOptions,
    cookies: cookieMethods,
  });
}
