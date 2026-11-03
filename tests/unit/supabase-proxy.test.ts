import type { CookieMethodsServer } from "@supabase/ssr";
import { unstable_doesMiddlewareMatch } from "next/experimental/testing/server";
import { NextRequest } from "next/server";
import { describe, expect, it, vi } from "vitest";

import { updateSupabaseSession } from "@/lib/supabase/proxy";
import { config } from "@/proxy";

vi.mock("server-only", () => ({}));

describe("Supabase session proxy", () => {
  it("refreshes an existing session without creating an anonymous user", async () => {
    const getUser = vi.fn().mockResolvedValue({
      data: { user: null },
      error: null,
    });
    const signInAnonymously = vi.fn();
    const request = new NextRequest("https://example.test/game");

    await updateSupabaseSession(request, () => ({
      auth: { getUser, signInAnonymously },
    }));

    expect(getUser).toHaveBeenCalledOnce();
    expect(signInAnonymously).not.toHaveBeenCalled();
  });

  it("synchronizes refreshed cookies to the request and response", async () => {
    const request = new NextRequest("https://example.test/game", {
      headers: { cookie: "sb-session=old-session" },
    });

    const createClient = (cookieMethods: CookieMethodsServer) => ({
      auth: {
        async getUser() {
          await cookieMethods.setAll?.(
            [
              {
                name: "sb-session",
                value: "refreshed-session",
                options: {
                  httpOnly: true,
                  path: "/",
                  sameSite: "lax",
                  secure: true,
                },
              },
            ],
            {
              "Cache-Control": "private, no-store",
              Expires: "0",
            },
          );

          return { data: { user: { id: "verified-user-id" } }, error: null };
        },
      },
    });

    const response = await updateSupabaseSession(request, createClient);

    expect(request.cookies.get("sb-session")?.value).toBe(
      "refreshed-session",
    );
    expect(response.cookies.get("sb-session")).toMatchObject({
      value: "refreshed-session",
      httpOnly: true,
      path: "/",
      sameSite: "lax",
      secure: true,
    });
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("expires")).toBe("0");
  });

  it("excludes static assets while keeping page and API requests covered", () => {
    const doesProxyMatch = (url: string) =>
      unstable_doesMiddlewareMatch({ config, nextConfig: {}, url });

    expect(doesProxyMatch("https://example.test/game")).toBe(true);
    expect(doesProxyMatch("https://example.test/api/game")).toBe(true);
    expect(
      doesProxyMatch("https://example.test/_next/static/chunks/app.js"),
    ).toBe(false);
    expect(doesProxyMatch("https://example.test/images/hero.webp")).toBe(
      false,
    );
  });
});
