import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createServerClient: vi.fn(),
  cookies: vi.fn(),
}));

vi.mock("server-only", () => ({}));
vi.mock("@supabase/ssr", () => ({
  createServerClient: mocks.createServerClient,
}));
vi.mock("next/headers", () => ({
  cookies: mocks.cookies,
}));
vi.mock("@/lib/supabase/server-config", () => ({
  getSupabasePublicConfig: () => ({
    url: "https://example.test",
    publishableKey: "test-publishable-key",
  }),
  supabaseAuthCookieOptions: {
    httpOnly: true,
    path: "/",
    sameSite: "lax",
  },
}));

import {
  createReadOnlyClient,
  createWritableClient,
} from "@/lib/supabase/server";

describe("Supabase server clients", () => {
  const cookieStore = {
    getAll: vi.fn(() => [{ name: "sb-session", value: "session-value" }]),
    set: vi.fn(),
  };

  beforeEach(() => {
    mocks.createServerClient.mockReset();
    mocks.cookies.mockReset();
    cookieStore.getAll.mockClear();
    cookieStore.set.mockClear();
    mocks.cookies.mockResolvedValue(cookieStore);
    mocks.createServerClient.mockReturnValue({ client: "supabase" });
  });

  it("creates a read-only client without a cookie writer", async () => {
    await createReadOnlyClient();

    const cookieMethods = mocks.createServerClient.mock.calls[0]?.[2].cookies;

    expect(cookieMethods.getAll()).toEqual([
      { name: "sb-session", value: "session-value" },
    ]);
    expect(cookieMethods).not.toHaveProperty("setAll");
    expect(cookieStore.set).not.toHaveBeenCalled();
  });

  it("keeps a cookie writer on the writable client", async () => {
    await createWritableClient();

    const cookieMethods = mocks.createServerClient.mock.calls[0]?.[2].cookies;
    const updatedCookie = {
      name: "sb-session",
      value: "updated-session",
      options: { httpOnly: true, path: "/" },
    };

    cookieMethods.setAll([updatedCookie], {});

    expect(cookieStore.set).toHaveBeenCalledWith(
      updatedCookie.name,
      updatedCookie.value,
      updatedCookie.options,
    );
  });
});
