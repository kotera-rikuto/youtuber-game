declare const ideaTitleBrand: unique symbol;

export type IdeaTitle = string & {
  readonly [ideaTitleBrand]: true;
};

export class IdeaTitleError extends Error {
  constructor() {
    super("企画タイトルは1〜100文字で入力してください。");
    this.name = "IdeaTitleError";
  }
}

export function createIdeaTitle(rawTitle: string): IdeaTitle {
  const normalizedTitle = rawTitle.trim();
  const characterCount = Array.from(normalizedTitle).length;

  if (characterCount < 1 || characterCount > 100) {
    throw new IdeaTitleError();
  }

  return normalizedTitle as IdeaTitle;
}
