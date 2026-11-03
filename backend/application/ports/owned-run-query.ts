import type { UseCaseContext } from "@/backend/application/auth/authentication";

export type OwnedRunQuery = {
  actorUserId: UseCaseContext["actorUserId"];
  runId: string;
};
