import "server-only";

import type { Clock } from "@/backend/application/ports/clock";

export class SystemClock implements Clock {
  now(): Date {
    return new Date();
  }
}
