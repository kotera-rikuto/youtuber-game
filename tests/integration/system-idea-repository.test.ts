import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { requireUseCaseContext, type UseCaseContext } from "@/backend/application/auth/authentication";
import type { Database } from "@/backend/infrastructure/supabase/database.types";
import { SupabaseSystemIdeaRepository } from "@/backend/infrastructure/supabase/repositories/supabase-system-idea-repository";
import { validateLocalIntegrationEnvironment } from "@/scripts/repository-integration-environment.js";

vi.mock("server-only", () => ({}));

const localEnvironment = validateLocalIntegrationEnvironment({
  url: process.env.SUPABASE_INTEGRATION_URL,
  publishableKey: process.env.SUPABASE_INTEGRATION_PUBLISHABLE_KEY,
  secretKey: process.env.SUPABASE_INTEGRATION_SECRET_KEY,
  databaseUrl: process.env.SUPABASE_INTEGRATION_DB_URL,
});
const clientOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
    detectSessionInUrl: false,
  },
} as const;
const poolCases = [
  { postingStyle: "mainstream", specialtyCode: null },
  { postingStyle: "controversial", specialtyCode: null },
  { postingStyle: "idol", specialtyCode: null },
  { postingStyle: "specialized", specialtyCode: "baseball" },
  { postingStyle: "specialized", specialtyCode: "soccer" },
  { postingStyle: "specialized", specialtyCode: "gaming" },
  { postingStyle: "specialized", specialtyCode: "pc_gadgets" },
  { postingStyle: "specialized", specialtyCode: "science" },
  { postingStyle: "specialized", specialtyCode: "history_culture" },
  { postingStyle: "specialized", specialtyCode: "occult" },
  { postingStyle: "specialized", specialtyCode: "nature" },
  { postingStyle: "specialized", specialtyCode: "food_culture" },
  { postingStyle: "specialized", specialtyCode: "outdoor_survival" },
] as const;

let serviceClient: SupabaseClient<Database>;
let repository: SupabaseSystemIdeaRepository;
let runs: ReadonlyArray<{
  context: UseCaseContext;
  runId: string;
  postingStyle: (typeof poolCases)[number]["postingStyle"];
  specialtyCode: (typeof poolCases)[number]["specialtyCode"];
}>;

beforeAll(async () => {
  serviceClient = createClient<Database>(
    localEnvironment.url,
    localEnvironment.secretKey,
    clientOptions,
  );
  repository = new SupabaseSystemIdeaRepository(serviceClient);

  runs = await Promise.all(
    poolCases.map(async (poolCase, index) => {
      const userId = await createUser(`be028-pool-${index}`);
      const { data: runId, error } = await serviceClient.rpc("commit_start_game", {
        p_actor_user_id: userId,
        p_channel_name: `BE-028 pool ${index}`,
        p_posting_style: poolCase.postingStyle,
        ...(poolCase.specialtyCode
          ? { p_specialty_code: poolCase.specialtyCode }
          : {}),
      });
      if (error || !runId) {
        throw new Error(`Unable to create BE-028 pool fixture ${index}.`);
      }
      return {
        context: await contextFor(userId),
        runId,
        ...poolCase,
      };
    }),
  );
});

describe("SupabaseSystemIdeaRepository", () => {
  it.each(poolCases)(
    "resolves only the 50 $postingStyle/$specialtyCode templates pinned to the run",
    async (poolCase) => {
      const fixture = runs.find(
        (run) =>
          run.postingStyle === poolCase.postingStyle &&
          run.specialtyCode === poolCase.specialtyCode,
      );
      if (!fixture) {
        throw new Error("The expected pool fixture is missing.");
      }

      const pool = await repository.findPool({
        actorUserId: fixture.context.actorUserId,
        runId: fixture.runId,
      });

      expect(pool).toHaveLength(50);
      expect(new Set(pool?.map((idea) => idea.templateId)).size).toBe(50);
      const { data: templates, error } = await serviceClient
        .from("system_idea_templates")
        .select("id,channel_type_code,specialty_code,enabled")
        .in("id", pool?.map((idea) => idea.templateId) ?? []);
      expect(error).toBeNull();
      expect(templates).toHaveLength(50);
      expect(
        templates?.every(
          (template) =>
            template.enabled &&
            template.channel_type_code === poolCase.postingStyle &&
            template.specialty_code === poolCase.specialtyCode,
        ),
      ).toBe(true);
    },
  );

  it("excludes a disabled template and exposes the invalid 49-entry pool", async () => {
    const fixture = runs.find((run) => run.postingStyle === "mainstream");
    if (!fixture) {
      throw new Error("The mainstream fixture is missing.");
    }
    const { error: disableError } = await serviceClient
      .from("system_idea_templates")
      .update({ enabled: false })
      .eq("code", "mainstream_001");
    expect(disableError).toBeNull();

    try {
      await expect(
        repository.findPool({
          actorUserId: fixture.context.actorUserId,
          runId: fixture.runId,
        }),
      ).resolves.toHaveLength(49);
    } finally {
      const { error: restoreError } = await serviceClient
        .from("system_idea_templates")
        .update({ enabled: true })
        .eq("code", "mainstream_001");
      if (restoreError) {
        throw new Error("Unable to restore the disabled system idea fixture.");
      }
    }
  });

  it("does not resolve a run for a different owner", async () => {
    const fixture = runs[0]!;
    const otherUserId = await createUser("be028-other-owner");
    const otherContext = await contextFor(otherUserId);

    await expect(
      repository.findPool({
        actorUserId: otherContext.actorUserId,
        runId: fixture.runId,
      }),
    ).resolves.toBeNull();
  });

  it("commits only one cycle when two requests race for the same run", async () => {
    const fixture = runs[0]!;
    const query = {
      actorUserId: fixture.context.actorUserId,
      runId: fixture.runId,
    };
    const pool = await repository.findPool(query);
    if (!pool) {
      throw new Error("The concurrent-cycle pool is missing.");
    }

    const orderedIds = pool.map((idea) => idea.ruleSetSystemIdeaId);
    const attempts = await Promise.all([
      repository.commitCycle({
        ...query,
        requiredCount: 7,
        orderedRuleSetSystemIdeaIds: orderedIds,
      }),
      repository.commitCycle({
        ...query,
        requiredCount: 7,
        orderedRuleSetSystemIdeaIds: [...orderedIds].reverse(),
      }),
    ]);

    expect(attempts[0]?.cycleId).toBe(attempts[1]?.cycleId);
    const cycles = await repository.listCycles(query);
    expect(cycles).toHaveLength(1);
    expect(cycles?.[0]?.entries).toHaveLength(50);
    expect(new Set(cycles?.[0]?.entries.map((entry) => entry.position)).size).toBe(
      50,
    );
  });
});

async function createUser(label: string) {
  const { data, error } = await serviceClient.auth.admin.createUser({
    email: `${label}-${crypto.randomUUID()}@example.test`,
    password: "BE-028-local-password",
    email_confirm: true,
  });
  if (error) {
    throw new Error(`Unable to create ${label} integration user.`);
  }
  return data.user.id;
}

function contextFor(userId: string) {
  return requireUseCaseContext({
    getVerifiedUser: async () => ({ status: "authenticated", userId }),
  });
}
