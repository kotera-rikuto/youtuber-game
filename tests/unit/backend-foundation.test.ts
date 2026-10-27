import packageMetadata from "@/package.json";
import { describe, expect, it } from "vitest";

describe("backend test foundation", () => {
  it("runs without browser DOM globals", () => {
    expect("window" in globalThis).toBe(false);
    expect("document" in globalThis).toBe(false);
  });

  it("resolves the TypeScript @ path alias", () => {
    expect(packageMetadata.name).toBe("youtuber-game");
  });
});
