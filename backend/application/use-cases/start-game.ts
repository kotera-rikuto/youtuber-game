import type { UseCaseContext } from "@/backend/application/auth/authentication";
import {
  StartGameCommitError,
  type GameRunRepository,
  type StartGameCommand,
} from "@/backend/application/ports/game-run-repository";
import type { RuleRepository } from "@/backend/application/ports/rule-repository";
import {
  POSTING_STYLES,
  SPECIALTY_CODES,
  type PostingStyle,
  type SpecialtyCode,
} from "@/backend/domain/game/rules";

type NonSpecializedPostingStyle = Exclude<PostingStyle, "specialized">;

export type StartGameInput =
  | {
      channelName: string;
      postingStyle: "specialized";
      specialtyCode: SpecialtyCode;
    }
  | {
      channelName: string;
      postingStyle: NonSpecializedPostingStyle;
      specialtyCode?: never;
    };

export type StartGameResult = {
  runId: string;
};

export type StartGameErrorCode =
  | "ACTIVE_GAME_EXISTS"
  | "RULES_UNAVAILABLE"
  | "SPECIALTY_REQUIRED"
  | "SPECIALTY_NOT_ALLOWED"
  | "VALIDATION_ERROR";

export class StartGameError extends Error {
  constructor(readonly code: StartGameErrorCode) {
    super("ゲームを開始できませんでした。");
    this.name = "StartGameError";
  }
}

export type StartGameDependencies = {
  gameRuns: GameRunRepository;
  rules: RuleRepository;
};

const postingStyleValues: ReadonlySet<string> = new Set(POSTING_STYLES);
const specialtyCodeValues: ReadonlySet<string> = new Set(SPECIALTY_CODES);

export async function startGame(
  context: UseCaseContext,
  input: StartGameInput,
  dependencies: StartGameDependencies,
): Promise<StartGameResult> {
  const command = validateInput(context, input);

  if (await dependencies.gameRuns.findActiveByOwner(context.actorUserId)) {
    throw new StartGameError("ACTIVE_GAME_EXISTS");
  }

  const activeRuleSet = await dependencies.rules.findActiveRuleSet();
  if (!activeRuleSet) {
    throw new StartGameError("RULES_UNAVAILABLE");
  }

  const channelRules = await dependencies.rules.listChannelRules(
    activeRuleSet.id,
  );
  if (
    !channelRules.some(
      (rule) => rule.channelTypeCode === command.postingStyle,
    )
  ) {
    throw new StartGameError("VALIDATION_ERROR");
  }

  if (command.postingStyle === "specialized") {
    const specialties = await dependencies.rules.listSpecialties(
      activeRuleSet.id,
    );
    if (
      !specialties.some(
        (specialty) => specialty.specialtyCode === command.specialtyCode,
      )
    ) {
      throw new StartGameError("SPECIALTY_NOT_ALLOWED");
    }
  }

  try {
    return await dependencies.gameRuns.commitStartGame(command);
  } catch (error) {
    if (error instanceof StartGameCommitError) {
      throw mapCommitError(error);
    }
    throw error;
  }
}

function validateInput(
  context: UseCaseContext,
  input: StartGameInput,
): StartGameCommand {
  const channelName = input.channelName.trim();
  if (channelName.length === 0 || !postingStyleValues.has(input.postingStyle)) {
    throw new StartGameError("VALIDATION_ERROR");
  }

  const runtimeSpecialtyCode = (input as { specialtyCode?: unknown })
    .specialtyCode;

  if (input.postingStyle === "specialized") {
    if (
      typeof runtimeSpecialtyCode !== "string" ||
      runtimeSpecialtyCode.length === 0
    ) {
      throw new StartGameError("SPECIALTY_REQUIRED");
    }
    if (!specialtyCodeValues.has(runtimeSpecialtyCode)) {
      throw new StartGameError("SPECIALTY_NOT_ALLOWED");
    }

    return {
      actorUserId: context.actorUserId,
      channelName,
      postingStyle: input.postingStyle,
      specialtyCode: runtimeSpecialtyCode as SpecialtyCode,
    };
  }

  if (runtimeSpecialtyCode !== undefined) {
    throw new StartGameError("SPECIALTY_NOT_ALLOWED");
  }

  return {
    actorUserId: context.actorUserId,
    channelName,
    postingStyle: input.postingStyle,
    specialtyCode: null,
  };
}

function mapCommitError(error: StartGameCommitError): StartGameError {
  switch (error.code) {
    case "ACTIVE_GAME_EXISTS":
    case "RULES_UNAVAILABLE":
    case "SPECIALTY_REQUIRED":
    case "SPECIALTY_NOT_ALLOWED":
    case "VALIDATION_ERROR":
      return new StartGameError(error.code);
    case "COMMIT_FAILED":
      return new StartGameError("RULES_UNAVAILABLE");
  }
}
