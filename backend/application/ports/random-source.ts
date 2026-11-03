export interface RandomSource {
  nextInt(minInclusive: number, maxInclusive: number): number;
}
