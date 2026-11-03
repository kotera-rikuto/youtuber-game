export type RepositoryErrorCode = "QUERY_FAILED" | "INVALID_DATA";

export class RepositoryError extends Error {
  constructor(
    readonly code: RepositoryErrorCode,
    readonly operation: string,
  ) {
    super(`Repository operation failed: ${operation}`);
    this.name = "RepositoryError";
  }
}
