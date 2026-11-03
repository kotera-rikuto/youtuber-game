import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const projectRoot = fileURLToPath(new URL("..", import.meta.url));
const suppliedEnvironment = {
  url: process.env.SUPABASE_INTEGRATION_URL,
  publishableKey: process.env.SUPABASE_INTEGRATION_PUBLISHABLE_KEY,
  secretKey: process.env.SUPABASE_INTEGRATION_SECRET_KEY,
  databaseUrl: process.env.SUPABASE_INTEGRATION_DB_URL,
};

const integrationEnvironment = hasCompleteEnvironment(suppliedEnvironment)
  ? suppliedEnvironment
  : readLocalSupabaseEnvironment();

const vitest = spawnSync(
  fileURLToPath(new URL("../node_modules/.bin/vitest", import.meta.url)),
  ["run", "tests/integration"],
  {
    cwd: projectRoot,
    env: {
      ...process.env,
      SUPABASE_INTEGRATION_URL: integrationEnvironment.url,
      SUPABASE_INTEGRATION_PUBLISHABLE_KEY:
        integrationEnvironment.publishableKey,
      SUPABASE_INTEGRATION_SECRET_KEY: integrationEnvironment.secretKey,
      SUPABASE_INTEGRATION_DB_URL: integrationEnvironment.databaseUrl,
    },
    stdio: "inherit",
  },
);

if (vitest.error) {
  console.error("Unable to start repository integration tests.");
  process.exitCode = 1;
} else {
  process.exitCode = vitest.status ?? 1;
}

function readLocalSupabaseEnvironment() {
  const supabase = spawnSync(
    fileURLToPath(new URL("../node_modules/.bin/supabase", import.meta.url)),
    ["status", "-o", "env"],
    {
      cwd: projectRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        SUPABASE_TELEMETRY_DISABLED: "true",
      },
    },
  );

  if (supabase.error || supabase.status !== 0) {
    console.error(
      "Local Supabase is unavailable. Start it with `npm run db:start` or provide SUPABASE_INTEGRATION_* variables.",
    );
    process.exit(1);
  }

  const variables = Object.fromEntries(
    supabase.stdout
      .split(/\r?\n/)
      .map((line) => line.match(/^([A-Z_]+)="(.*)"$/))
      .filter((match) => match !== null)
      .map((match) => [match[1], match[2]]),
  );
  const environment = {
    url: variables.API_URL,
    publishableKey: variables.PUBLISHABLE_KEY,
    secretKey: variables.SECRET_KEY,
    databaseUrl: variables.DB_URL,
  };

  if (!hasCompleteEnvironment(environment)) {
    console.error("Local Supabase did not return all required test credentials.");
    process.exit(1);
  }

  return environment;
}

function hasCompleteEnvironment(environment) {
  return Object.values(environment).every(
    (value) => typeof value === "string" && value.length > 0,
  );
}
