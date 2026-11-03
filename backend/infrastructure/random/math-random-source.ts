import "server-only";

import type { RandomSource } from "@/backend/application/ports/random-source";

export class MathRandomSource implements RandomSource {
  nextInt(minInclusive: number, maxInclusive: number): number {
    validateInclusiveIntegerRange(minInclusive, maxInclusive);
    if (minInclusive === maxInclusive) {
      return minInclusive;
    }

    const rangeSize = maxInclusive - minInclusive + 1;
    if (!Number.isSafeInteger(rangeSize)) {
      throw new RangeError("Random integer range is too large.");
    }

    return Math.floor(Math.random() * rangeSize) + minInclusive;
  }
}

export function validateInclusiveIntegerRange(
  minInclusive: number,
  maxInclusive: number,
): void {
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
