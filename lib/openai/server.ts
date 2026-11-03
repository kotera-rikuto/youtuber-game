import "server-only";
import OpenAI from "openai";

type OpenAIClientOptions = {
  maxRetries?: number;
  timeoutMs?: number;
};

export function createOpenAIClient(options: OpenAIClientOptions = {}) {
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    throw new Error("OPENAI_API_KEY が設定されていません。");
  }

  return new OpenAI({
    apiKey,
    maxRetries: options.maxRetries,
    timeout: options.timeoutMs,
  });
}
