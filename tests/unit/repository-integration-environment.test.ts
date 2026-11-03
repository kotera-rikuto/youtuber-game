import { describe, expect, it, vi } from "vitest";

import {
  startWithLocalIntegrationEnvironment,
  validateLocalIntegrationEnvironment,
} from "@/scripts/repository-integration-environment.js";

const credentials = {
  publishableKey: "local-publishable-key",
  secretKey: "local-secret-key",
};

describe("repository integration environment safety", () => {
  it.each([
    [
      "localhost",
      "http://localhost:54321",
      "postgresql://postgres:postgres@localhost:54322/postgres",
    ],
    [
      "127.0.0.1",
      "http://127.0.0.1:54321",
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
    ],
    [
      "IPv6 loopback",
      "http://[::1]:54321",
      "postgresql://postgres:postgres@[::1]:54322/postgres",
    ],
  ])("allows %s for both local connections", (_name, url, databaseUrl) => {
    expect(
      validateLocalIntegrationEnvironment({
        ...credentials,
        url,
        databaseUrl,
      }),
    ).toEqual({ ...credentials, url, databaseUrl });
  });

  it("rejects a remote Supabase API URL", () => {
    expect(() =>
      validateLocalIntegrationEnvironment({
        ...credentials,
        url: "https://example.supabase.co",
        databaseUrl:
          "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
      }),
    ).toThrow("loopback host");
  });

  it("rejects an external PostgreSQL host", () => {
    expect(() =>
      validateLocalIntegrationEnvironment({
        ...credentials,
        url: "http://127.0.0.1:54321",
        databaseUrl:
          "postgresql://postgres:password@database.example.com:5432/postgres",
      }),
    ).toThrow("loopback host");
  });

  it.each([
    ["invalid API URL", "not-a-url", "postgresql://postgres:postgres@localhost:54322/postgres"],
    ["invalid database URL", "http://localhost:54321", "not-a-url"],
  ])("rejects an %s", (_name, url, databaseUrl) => {
    expect(() =>
      validateLocalIntegrationEnvironment({
        ...credentials,
        url,
        databaseUrl,
      }),
    ).toThrow("invalid");
  });

  it("rejects incomplete connection information", () => {
    expect(() =>
      validateLocalIntegrationEnvironment({
        url: "http://localhost:54321",
        databaseUrl:
          "postgresql://postgres:postgres@localhost:54322/postgres",
      }),
    ).toThrow("required test credentials");
  });

  it("rejects a remote connection before starting Vitest or psql", () => {
    const start = vi.fn();

    expect(() =>
      startWithLocalIntegrationEnvironment(
        {
          ...credentials,
          url: "https://example.supabase.co",
          databaseUrl:
            "postgresql://postgres:password@database.example.com:5432/postgres",
        },
        start,
      ),
    ).toThrow("loopback host");
    expect(start).not.toHaveBeenCalled();
  });
});
