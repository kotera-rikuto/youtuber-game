import type { RandomSource } from "@/backend/application/ports/random-source";

export class SequenceRandomSource implements RandomSource {
  private nextIndex = 0;

  constructor(private readonly sequence: readonly number[]) {}

  nextInt(minInclusive: number, maxInclusive: number): number {
    validateRange(minInclusive, maxInclusive);
    const value = this.sequence[this.nextIndex];
    if (value === undefined) {
      throw new Error("SequenceRandomSource has no values remaining.");
    }
    if (value < minInclusive || value > maxInclusive) {
      throw new RangeError(
        "SequenceRandomSource value is outside the requested inclusive range.",
      );
    }
    if (!Number.isSafeInteger(value)) {
      throw new RangeError("SequenceRandomSource values must be safe integers.");
    }

    this.nextIndex += 1;
    return value;
  }

  get consumedCount(): number {
    return this.nextIndex;
  }
}

function validateRange(minInclusive: number, maxInclusive: number): void {
  if (
    !Number.isSafeInteger(minInclusive) ||
    !Number.isSafeInteger(maxInclusive)
  ) {
    throw new RangeError("Random integer bounds must be safe integers.");
  }
  if (minInclusive > maxInclusive) {
    throw new RangeError(
      "Random integer minimum must not exceed the maximum.",
    );
  }
}
