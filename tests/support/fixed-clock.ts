import type { Clock } from "@/backend/application/ports/clock";

export class FixedClock implements Clock {
  private readonly fixedTimestamp: number;

  constructor(fixedTime: Date) {
    const timestamp = fixedTime.getTime();
    if (Number.isNaN(timestamp)) {
      throw new RangeError("Fixed clock requires a valid date.");
    }
    this.fixedTimestamp = timestamp;
  }

  now(): Date {
    return new Date(this.fixedTimestamp);
  }
}
