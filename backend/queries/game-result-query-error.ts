export type GameResultQueryErrorCode =
  | "NOT_FOUND"
  | "INVALID_STATE"
  | "DATA_INTEGRITY_ERROR"
  | "QUERY_FAILED";

export class GameResultQueryError extends Error {
  constructor(readonly code: GameResultQueryErrorCode) {
    super("ゲーム結果を取得できませんでした。");
    this.name = "GameResultQueryError";
  }
}
