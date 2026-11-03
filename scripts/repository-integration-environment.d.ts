export type LocalIntegrationEnvironment = {
  url: string;
  publishableKey: string;
  secretKey: string;
  databaseUrl: string;
};

export function extractSupabaseStatusEnvironment(statusOutput: string): {
  url: string | undefined;
  publishableKey: string | undefined;
  secretKey: string | undefined;
  databaseUrl: string | undefined;
};

export function validateLocalIntegrationEnvironment(
  environment: Partial<LocalIntegrationEnvironment> | null | undefined,
): LocalIntegrationEnvironment;

export function startWithLocalIntegrationEnvironment<T>(
  environment: Partial<LocalIntegrationEnvironment> | null | undefined,
  start: (environment: LocalIntegrationEnvironment) => T,
): T;
