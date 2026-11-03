const loopbackHostnames = new Set(["localhost", "127.0.0.1", "::1"]);

export function extractSupabaseStatusEnvironment(statusOutput) {
  const variables = Object.fromEntries(
    statusOutput
      .split(/\r?\n/)
      .map((line) => line.match(/^([A-Z_]+)="(.*)"$/))
      .filter((match) => match !== null)
      .map((match) => [match[1], match[2]]),
  );

  return {
    url: variables.API_URL,
    publishableKey: variables.PUBLISHABLE_KEY,
    secretKey: variables.SECRET_KEY,
    databaseUrl: variables.DB_URL,
  };
}

export function validateLocalIntegrationEnvironment(environment) {
  if (
    !environment ||
    !isNonemptyString(environment.url) ||
    !isNonemptyString(environment.publishableKey) ||
    !isNonemptyString(environment.secretKey) ||
    !isNonemptyString(environment.databaseUrl)
  ) {
    throw new Error("Local Supabase did not return all required test credentials.");
  }

  requireLoopbackUrl(environment.url, new Set(["http:", "https:"]), "API");
  requireLoopbackUrl(
    environment.databaseUrl,
    new Set(["postgres:", "postgresql:"]),
    "database",
  );

  return environment;
}

export function startWithLocalIntegrationEnvironment(environment, start) {
  const validatedEnvironment = validateLocalIntegrationEnvironment(environment);
  return start(validatedEnvironment);
}

function requireLoopbackUrl(value, allowedProtocols, connectionName) {
  let parsedUrl;
  try {
    parsedUrl = new URL(value);
  } catch {
    throw new Error(`${connectionName} connection URL is invalid.`);
  }

  const hostname = parsedUrl.hostname.replace(/^\[|\]$/g, "").toLowerCase();
  if (
    !allowedProtocols.has(parsedUrl.protocol) ||
    !loopbackHostnames.has(hostname)
  ) {
    throw new Error(
      `${connectionName} connection must use the local Supabase loopback host.`,
    );
  }
}

function isNonemptyString(value) {
  return typeof value === "string" && value.length > 0;
}
