import "server-only";
import OpenAI from "openai";

export function createOpenAIClient() {
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    throw new Error("OPENAI_API_KEY が設定されていません。");
  }

  return new OpenAI({ apiKey });
}
