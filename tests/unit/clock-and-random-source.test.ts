import { afterEach, describe, expect, it, vi } from "vitest";

import { MathRandomSource } from "@/backend/infrastructure/random/math-random-source";
import { SystemClock } from "@/backend/infrastructure/time/system-clock";
import { FixedClock } from "@/tests/support/fixed-clock";
import { SequenceRandomSource } from "@/tests/support/sequence-random-source";

vi.mock("server-only", () => ({}));

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Clock", () => {
  it("returns the fixed time without exposing its mutable Date instance", () => {
    const source = new Date("2026-11-03T12:00:00.000Z");
    const clock = new FixedClock(source);
    source.setUTCFullYear(2000);

    const first = clock.now();
    first.setUTCFullYear(1999);

    expect(clock.now()).toEqual(new Date("2026-11-03T12:00:00.000Z"));
  });

  it("provides a real infrastructure clock", () => {
    const clock = new SystemClock();
    expect(clock.now()).toBeInstanceOf(Date);
  });
});

describe("RandomSource", () => {
  it("returns the inclusive minimum", () => {
    vi.spyOn(Math, "random").mockReturnValue(0);
    expect(new MathRandomSource().nextInt(2, 5)).toBe(2);
  });

  it("returns the inclusive maximum", () => {
    vi.spyOn(Math, "random").mockReturnValue(0.9999999999999999);
    expect(new MathRandomSource().nextInt(2, 5)).toBe(5);
  });

  it("returns the only possible value without consuming randomness", () => {
    const random = vi.spyOn(Math, "random");
    expect(new MathRandomSource().nextInt(4, 4)).toBe(4);
    expect(random).not.toHaveBeenCalled();
  });

  it.each([
    [2, 1],
    [1.5, 2],
    [1, 2.5],
    [Number.NaN, 2],
  ])("rejects an invalid inclusive range (%s, %s)", (min, max) => {
    expect(() => new MathRandomSource().nextInt(min, max)).toThrow(RangeError);
  });

  it("returns a fixed sequence in order", () => {
    const random = new SequenceRandomSource([2, 5, 3]);
    expect(random.nextInt(1, 5)).toBe(2);
    expect(random.nextInt(1, 5)).toBe(5);
    expect(random.nextInt(1, 5)).toBe(3);
    expect(random.consumedCount).toBe(3);
  });

  it("fails when the fixed sequence is exhausted", () => {
    const random = new SequenceRandomSource([1]);
    random.nextInt(1, 1);
    expect(() => random.nextInt(1, 1)).toThrow("no values remaining");
  });

  it("fails when a fixed value is outside the requested range", () => {
    expect(() => new SequenceRandomSource([6]).nextInt(1, 5)).toThrow(
      RangeError,
    );
  });
});
