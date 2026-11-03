import type { UseCaseContext } from "@/backend/application/auth/authentication";
import type { OwnedRunQuery } from "@/backend/application/ports/owned-run-query";
import type { GameRun } from "@/backend/domain/game/game-run";

export interface GameRunRepository {
  findActiveByOwner(
    actorUserId: UseCaseContext["actorUserId"],
  ): Promise<GameRun | null>;
  findCurrentById(query: OwnedRunQuery): Promise<GameRun | null>;
}
