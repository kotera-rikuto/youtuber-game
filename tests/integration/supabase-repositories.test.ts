import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import {
  requireUseCaseContext,
  type UseCaseContext,
} from "@/backend/application/auth/authentication";
import { StartGameCommitError } from "@/backend/application/ports/game-run-repository";
import { RepositoryError } from "@/backend/application/ports/repository-error";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { createSupabaseRepositories } from "@/backend/infrastructure/supabase/repositories/create-repositories";
import { SupabaseRuleRepository } from "@/backend/infrastructure/supabase/repositories/supabase-rule-repository";
import { getGameStartOptionsDTO } from "@/backend/queries/get-game-start-options";
import { validateLocalIntegrationEnvironment } from "@/scripts/repository-integration-environment.js";

vi.mock("server-only", () => ({}));

const fixturePath = fileURLToPath(
  new URL("./fixtures/repository-read-models.sql", import.meta.url),
);
const localEnvironment = readIntegrationEnvironment();
const ownerCredentials = {
  email: "be013-owner@example.test",
  password: "BE-013-local-password",
};
const otherCredentials = {
  email: "be013-other@example.test",
  password: "BE-013-local-password",
};
const startGameCredentials = {
  email: `be015-start-${crypto.randomUUID()}@example.test`,
  password: "BE-015-local-password",
};
const concurrentStartCredentials = {
  email: `be015-concurrent-${crypto.randomUUID()}@example.test`,
  password: "BE-015-local-password",
};
const ownerRunId = "00000000-0000-4000-8000-00000000b013";
const draftRuleSetId = "00000000-0000-4000-8000-00000000f013";

let ownerContext: UseCaseContext;
let otherContext: UseCaseContext;
let startGameContext: UseCaseContext;
let concurrentStartContext: UseCaseContext;
let ownerClient: SupabaseClient<Database>;
let otherClient: SupabaseClient<Database>;
let serviceClient: SupabaseClient<Database>;

beforeAll(async () => {
  serviceClient = createClient<Database>(
    localEnvironment.url,
    localEnvironment.secretKey,
    clientOptions,
  );
  const owner = await ensureTestUser(serviceClient, ownerCredentials);
  const other = await ensureTestUser(serviceClient, otherCredentials);
  const startGameUser = await ensureTestUser(serviceClient, startGameCredentials);
  const concurrentStartUser = await ensureTestUser(
    serviceClient,
    concurrentStartCredentials,
  );

  execFileSync(
    "psql",
    [
      localEnvironment.databaseUrl,
      "-v",
      `owner_user_id=${owner.id}`,
      "-v",
      `other_user_id=${other.id}`,
      "-f",
      fixturePath,
    ],
    { stdio: "pipe" },
  );

  const { error: draftError } = await serviceClient.from("rule_sets").upsert({
    id: draftRuleSetId,
    version: "be013-draft",
    status: "draft",
    published_at: null,
  });
  if (draftError) {
    throw new Error("Unable to prepare the draft rule-set fixture.");
  }

  ownerClient = await signIn(ownerCredentials);
  otherClient = await signIn(otherCredentials);
  ownerContext = await contextFor(owner.id);
  otherContext = await contextFor(other.id);
  startGameContext = await contextFor(startGameUser.id);
  concurrentStartContext = await contextFor(concurrentStartUser.id);

  process.env.NEXT_PUBLIC_SUPABASE_URL = localEnvironment.url;
  process.env.SUPABASE_SECRET_KEY = localEnvironment.secretKey;
});

describe("Supabase repository integration", () => {
  it("maps an owned current game view into the domain aggregate", async () => {
    const repositories = createSupabaseRepositories(ownerClient);

    const game = await repositories.gameRuns.findActiveByOwner(
      ownerContext.actorUserId,
    );

    expect(game).toMatchObject({
      id: ownerRunId,
      ownerUserId: ownerContext.actorUserId,
      channelName: "BE-013 Owner Channel",
      channelType: { code: "mainstream" },
      currentState: { currentWeek: 4, stateVersion: 2 },
    });
    expect(game?.abilities).toHaveLength(6);
    expect(game?.createdAt).toBeInstanceOf(Date);
  });

  it("does not return another user's run", async () => {
    const repositories = createSupabaseRepositories(otherClient);

    await expect(
      repositories.gameRuns.findCurrentById({
        actorUserId: otherContext.actorUserId,
        runId: ownerRunId,
      }),
    ).resolves.toBeNull();
  });

  it("returns pending ideas in contiguous queue order", async () => {
    const repositories = createSupabaseRepositories(ownerClient);
    const query = {
      actorUserId: ownerContext.actorUserId,
      runId: ownerRunId,
    };

    const queue = await repositories.ideaStock.getPendingQueue(query);

    expect(queue?.items.map((idea) => idea.title)).toEqual([
      "Queue First",
      "Queue Second",
    ]);
    await expect(repositories.ideaStock.countPending(query)).resolves.toBe(2);
    await expect(
      repositories.ideaStock.countCreatedInWeek({ ...query, weekNumber: 4 }),
    ).resolves.toBe(2);
  });

  it("loads only active or run-pinned published rules", async () => {
    const repositories = createSupabaseRepositories(ownerClient);
    const active = await repositories.rules.findActiveRuleSet();
    expect(active?.status).toBe("active");
    if (!active) {
      throw new Error("The seeded active rule set is missing.");
    }

    await expect(
      repositories.rules.findPublishedRuleSetById(active.id),
    ).resolves.toEqual(active);
    await expect(
      repositories.rules.findPublishedRuleSetById(draftRuleSetId),
    ).resolves.toBeNull();
    await expect(repositories.rules.listChannelRules(active.id)).resolves.toHaveLength(
      4,
    );
    await expect(repositories.rules.listSpecialties(active.id)).resolves.toHaveLength(
      10,
    );
    await expect(
      repositories.rules.listPostingFrequencies(active.id),
    ).resolves.toHaveLength(3);
  });

  it("returns active game-start options without internal ids", async () => {
    const options = await getGameStartOptionsDTO();

    expect(options.postingStyles.map((option) => option.code)).toEqual([
      "mainstream",
      "specialized",
      "controversial",
      "idol",
    ]);
    expect(options.specialties).toHaveLength(10);
    expect(JSON.stringify(options)).not.toMatch(/rule_set_id|ruleSetId/);
  });

  it("commits game start through one repository command and maps duplicate errors", async () => {
    const repositories = createSupabaseRepositories(serviceClient);
    const command = {
      actorUserId: startGameContext.actorUserId,
      channelName: "Integration Start",
      postingStyle: "specialized" as const,
      specialtyCode: "gaming" as const,
    };

    const started = await repositories.gameRuns.commitStartGame(command);

    expect(started.runId).toMatch(/^[0-9a-f-]{36}$/);
    const { data: state, error } = await serviceClient
      .from("run_state")
      .select("current_week,cash,energy,state_version")
      .eq("run_id", started.runId)
      .single();
    expect(error).toBeNull();
    expect(state).toEqual({
      current_week: 1,
      cash: 100_000,
      energy: 100,
      state_version: 0,
    });

    await expect(
      repositories.gameRuns.commitStartGame(command),
    ).rejects.toMatchObject({
      name: "StartGameCommitError",
      code: "ACTIVE_GAME_EXISTS",
    } satisfies Partial<StartGameCommitError>);
  });

  it("allows only one winner when the same user starts concurrently", async () => {
    const repositories = createSupabaseRepositories(serviceClient);
    const command = {
      actorUserId: concurrentStartContext.actorUserId,
      channelName: "Concurrent Start",
      postingStyle: "mainstream" as const,
      specialtyCode: null,
    };

    const attempts = await Promise.allSettled([
      repositories.gameRuns.commitStartGame(command),
      repositories.gameRuns.commitStartGame(command),
    ]);

    expect(attempts.filter((attempt) => attempt.status === "fulfilled")).toHaveLength(
      1,
    );
    const rejected = attempts.find(
      (attempt): attempt is PromiseRejectedResult =>
        attempt.status === "rejected",
    );
    expect(rejected?.reason).toMatchObject({
      name: "StartGameCommitError",
      code: "ACTIVE_GAME_EXISTS",
    });

    const { count, error } = await serviceClient
      .from("game_runs")
      .select("id", { count: "exact", head: true })
      .eq("user_id", concurrentStartContext.actorUserId)
      .in("status", ["playing", "stage_cleared"]);
    expect(error).toBeNull();
    expect(count).toBe(1);
  });

  it("returns committed week results in week-number order and by idempotency key", async () => {
    const repositories = createSupabaseRepositories(ownerClient);
    const query = {
      actorUserId: ownerContext.actorUserId,
      runId: ownerRunId,
    };

    const history = await repositories.weekResults.listHistory(query);

    expect(history?.map((result) => result.weekNumber)).toEqual([2, 3]);
    expect(history?.every((result) => result.createdAt instanceof Date)).toBe(
      true,
    );
    await expect(
      repositories.weekResults.findCommittedWeek({ ...query, weekNumber: 2 }),
    ).resolves.toMatchObject({ weekNumber: 2 });
    await expect(
      repositories.weekResults.findByIdempotencyKey({
        ...query,
        idempotencyKey: "00000000-0000-4000-8000-00000000d133",
      }),
    ).resolves.toMatchObject({ weekNumber: 3 });
  });

  it("converts a provider failure into RepositoryError instead of an empty result", async () => {
    const invalidClient = createClient<Database>(
      localEnvironment.url,
      "invalid-local-api-key",
      clientOptions,
    );
    const repository = new SupabaseRuleRepository(invalidClient);

    await expect(repository.findActiveRuleSet()).rejects.toMatchObject({
      name: "RepositoryError",
      code: "QUERY_FAILED",
      operation: "rule.findActiveRuleSet",
    } satisfies Partial<RepositoryError>);
  });
});

const clientOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
    detectSessionInUrl: false,
  },
} as const;

async function ensureTestUser(
  client: SupabaseClient<Database>,
  credentials: { email: string; password: string },
): Promise<User> {
  const { data: listedUsers, error: listError } = await client.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listError) {
    throw new Error("Unable to list local integration-test users.");
  }

  const existing = listedUsers.users.find(
    (user) => user.email === credentials.email,
  );
  if (existing) {
    const { data, error } = await client.auth.admin.updateUserById(existing.id, {
      password: credentials.password,
      email_confirm: true,
    });
    if (error) {
      throw new Error("Unable to refresh a local integration-test user.");
    }
    return data.user;
  }

  const { data, error } = await client.auth.admin.createUser({
    ...credentials,
    email_confirm: true,
  });
  if (error) {
    throw new Error("Unable to create a local integration-test user.");
  }
  return data.user;
}

async function signIn(credentials: { email: string; password: string }) {
  const client = createClient<Database>(
    localEnvironment.url,
    localEnvironment.publishableKey,
    clientOptions,
  );
  const { error } = await client.auth.signInWithPassword(credentials);
  if (error) {
    throw new Error("Unable to sign in a local integration-test user.");
  }
  return client;
}

function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}

function readIntegrationEnvironment() {
  return validateLocalIntegrationEnvironment({
    url: process.env.SUPABASE_INTEGRATION_URL,
    publishableKey: process.env.SUPABASE_INTEGRATION_PUBLISHABLE_KEY,
    secretKey: process.env.SUPABASE_INTEGRATION_SECRET_KEY,
    databaseUrl: process.env.SUPABASE_INTEGRATION_DB_URL,
  });
}
