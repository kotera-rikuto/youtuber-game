import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { GameRunRepository } from "@/backend/application/ports/game-run-repository";
import type { FinalGameRun, GameRun } from "@/backend/domain/game/game-run";

export type GameResultQuerySource = Pick<
  GameRunRepository,
  "findCurrentById" | "findFinalById"
>;

export type GameResultQueryInput = OwnedRunQuery;

export type CurrentGameSourceResult = Promise<GameRun | null>;
export type FinalGameSourceResult = Promise<FinalGameRun | null>;
