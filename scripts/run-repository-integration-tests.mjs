import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import {
  extractSupabaseStatusEnvironment,
  startWithLocalIntegrationEnvironment,
} from "./repository-integration-environment.js";

const projectRoot = fileURLToPath(new URL("..", import.meta.url));
const integrationEnvironment = extractSupabaseStatusEnvironment(
  readLocalSupabaseStatus(),
);
const vitest = startWithLocalIntegrationEnvironment(
  integrationEnvironment,
  startVitest,
);

if (vitest.error) {
  console.error("Unable to start repository integration tests.");
  process.exitCode = 1;
} else {
  process.exitCode = vitest.status ?? 1;
}

function readLocalSupabaseStatus() {
  const supabase = spawnSync(
    fileURLToPath(new URL("../node_modules/.bin/supabase", import.meta.url)),
    ["status", "-o", "env"],
    {
      cwd: projectRoot,
      encoding: "utf8",
      env: {
        ...createSanitizedProcessEnvironment(),
        SUPABASE_TELEMETRY_DISABLED: "true",
      },
    },
  );

  if (supabase.error || supabase.status !== 0) {
    console.error(
      "Local Supabase is unavailable. Start it with `npm run db:start`.",
    );
    process.exit(1);
  }

  return supabase.stdout;
}

function startVitest(environment) {
  return spawnSync(
    fileURLToPath(new URL("../node_modules/.bin/vitest", import.meta.url)),
    ["run", "tests/integration"],
    {
      cwd: projectRoot,
      env: {
        ...createSanitizedProcessEnvironment(),
        SUPABASE_INTEGRATION_URL: environment.url,
        SUPABASE_INTEGRATION_PUBLISHABLE_KEY: environment.publishableKey,
        SUPABASE_INTEGRATION_SECRET_KEY: environment.secretKey,
        SUPABASE_INTEGRATION_DB_URL: environment.databaseUrl,
      },
      stdio: "inherit",
    },
  );
}

function createSanitizedProcessEnvironment() {
  const environment = { ...process.env };
  delete environment.SUPABASE_INTEGRATION_URL;
  delete environment.SUPABASE_INTEGRATION_PUBLISHABLE_KEY;
  delete environment.SUPABASE_INTEGRATION_SECRET_KEY;
  delete environment.SUPABASE_INTEGRATION_DB_URL;
  return environment;
}
