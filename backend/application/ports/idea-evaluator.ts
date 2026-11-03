export const IDEA_EVALUATION_FALLBACK_SCORE = 60;

export type IdeaEvaluationInput = {
  title: string;
  channelType: string;
  specialty: string | null;
};

export type IdeaEvaluationResult =
  | {
      score: number;
      status: "completed";
    }
  | {
      score: typeof IDEA_EVALUATION_FALLBACK_SCORE;
      status: "fallback";
    };

export interface IdeaEvaluator {
  evaluate(input: IdeaEvaluationInput): Promise<IdeaEvaluationResult>;
}
