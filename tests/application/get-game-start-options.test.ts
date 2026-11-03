import { beforeAll, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

const postingStyles = [
  { code: "idol", name: "アイドル系", display_order: 4 },
  { code: "mainstream", name: "王道系", display_order: 1 },
  { code: "controversial", name: "炎上系", display_order: 3 },
  { code: "specialized", name: "特化系", display_order: 2 },
];
const specialties = [
  ["outdoor_survival", "アウトドア・サバイバル", 10],
  ["baseball", "野球", 1],
  ["soccer", "サッカー", 2],
  ["gaming", "ゲーム攻略・検証", 3],
  ["pc_gadgets", "PC・ガジェット", 4],
  ["science", "科学・実験", 5],
  ["history_culture", "歴史・文化", 6],
  ["occult", "心霊・オカルト", 7],
  ["nature", "生き物・自然", 8],
  ["food_culture", "料理・食文化", 9],
] as const;

let getGameStartOptionsDTO: typeof import("@/backend/queries/get-game-start-options").getGameStartOptionsDTO;

beforeAll(async () => {
  ({ getGameStartOptionsDTO } = await import(
    "@/backend/queries/get-game-start-options"
  ));
});

describe("getGameStartOptionsDTO", () => {
  it("returns four posting styles and ten specialties in stable display order", async () => {
    const options = await getGameStartOptionsDTO({
      loadActiveOptions: async () => ({
        postingStyles,
        specialties: specialties.map(([code, name, display_order]) => ({
          code,
          name,
          display_order,
        })),
      }),
    });

    expect(options.postingStyles).toHaveLength(4);
    expect(options.specialties).toHaveLength(10);
    expect(options.postingStyles.map((option) => option.code)).toEqual([
      "mainstream",
      "specialized",
      "controversial",
      "idol",
    ]);
    expect(options.specialties.map((option) => option.displayOrder)).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    ]);
  });

  it("maps database-shaped rows to DTOs without internal rule identifiers", async () => {
    const options = await getGameStartOptionsDTO({
      loadActiveOptions: async () => ({
        postingStyles,
        specialties: specialties.map(([code, name, display_order]) => ({
          code,
          name,
          display_order,
        })),
      }),
    });

    expect(options.postingStyles[0]).toEqual({
      code: "mainstream",
      name: "王道系",
      displayOrder: 1,
    });
    expect(JSON.stringify(options)).not.toMatch(
      /ruleSetId|rule_set_id|channelRuleId|channel_rule_id/,
    );
  });
});
