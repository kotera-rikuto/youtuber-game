import { describe, expect, it } from "vitest";

import {
  createIdeaTitle,
  IdeaTitleError,
} from "@/backend/domain/game/idea-creation";

describe("createIdeaTitle", () => {
  it.each(["企", "企".repeat(100), "😀".repeat(100)])(
    "accepts a title at a PostgreSQL char_length boundary",
    (title) => {
      expect(createIdeaTitle(`  ${title}  `)).toBe(title);
    },
  );

  it.each(["", " \n\t ", "企".repeat(101), "😀".repeat(101)])(
    "rejects an empty or overlong title",
    (title) => {
      expect(() => createIdeaTitle(title)).toThrow(IdeaTitleError);
    },
  );
});
