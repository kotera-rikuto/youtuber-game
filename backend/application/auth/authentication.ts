declare const verifiedActorUserId: unique symbol;

type ActorUserId = string & {
  readonly [verifiedActorUserId]: true;
};

export type UseCaseContext = {
  actorUserId: ActorUserId;
};

export type VerifiedUserLookup =
  | { status: "authenticated"; userId: string }
  | { status: "unauthenticated" }
  | { status: "failed" };

export interface VerifiedUserGateway {
  getVerifiedUser(): Promise<VerifiedUserLookup>;
}

export interface AnonymousAuthenticationGateway extends VerifiedUserGateway {
  signInAnonymously(): Promise<"signed-in" | "failed">;
}

export class AuthenticationError extends Error {
  readonly code = "UNAUTHENTICATED";

  constructor() {
    super("認証済みユーザーを確認できませんでした。");
    this.name = "AuthenticationError";
  }
}

export async function requireUseCaseContext(
  authentication: VerifiedUserGateway,
): Promise<UseCaseContext> {
  const verifiedUser = await authentication.getVerifiedUser();
  return createUseCaseContext(verifiedUser);
}

export async function ensureAnonymousUserForGameStart(
  authentication: AnonymousAuthenticationGateway,
): Promise<UseCaseContext> {
  const currentUser = await authentication.getVerifiedUser();

  if (currentUser.status === "authenticated") {
    return createUseCaseContext(currentUser);
  }

  if (currentUser.status === "failed") {
    throw new AuthenticationError();
  }

  const signInStatus = await authentication.signInAnonymously();
  if (signInStatus === "failed") {
    throw new AuthenticationError();
  }

  const createdUser = await authentication.getVerifiedUser();
  return createUseCaseContext(createdUser);
}

function createUseCaseContext(
  verifiedUser: VerifiedUserLookup,
): UseCaseContext {
  if (
    verifiedUser.status !== "authenticated" ||
    verifiedUser.userId.length === 0
  ) {
    throw new AuthenticationError();
  }

  return {
    actorUserId: verifiedUser.userId as ActorUserId,
  };
}
