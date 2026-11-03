import "server-only";

import { DataIntegrityError } from "@/backend/domain/shared/data-integrity-error";

export function requireRecord(
  value: unknown,
  fieldName: string,
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new DataIntegrityError(`${fieldName} must be an object.`);
  }

  return value as Record<string, unknown>;
}

export function requireArray(
  value: unknown,
  fieldName: string,
): readonly unknown[] {
  if (!Array.isArray(value)) {
    throw new DataIntegrityError(`${fieldName} must be an array.`);
  }

  return value;
}

export function requireString(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new DataIntegrityError(`${fieldName} must be a non-empty string.`);
  }

  return value;
}

export function requireBoolean(value: unknown, fieldName: string): boolean {
  if (typeof value !== "boolean") {
    throw new DataIntegrityError(`${fieldName} must be a boolean.`);
  }

  return value;
}

export function requireFiniteNumber(
  value: unknown,
  fieldName: string,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new DataIntegrityError(`${fieldName} must be a finite number.`);
  }

  return value;
}

export function requireInteger(value: unknown, fieldName: string): number {
  const integer = requireFiniteNumber(value, fieldName);
  if (!Number.isSafeInteger(integer)) {
    throw new DataIntegrityError(`${fieldName} must be a safe integer.`);
  }

  return integer;
}

export function requireNonnegativeInteger(
  value: unknown,
  fieldName: string,
): number {
  const integer = requireInteger(value, fieldName);
  if (integer < 0) {
    throw new DataIntegrityError(`${fieldName} must not be negative.`);
  }

  return integer;
}

export function requirePositiveInteger(
  value: unknown,
  fieldName: string,
): number {
  const integer = requireInteger(value, fieldName);
  if (integer < 1) {
    throw new DataIntegrityError(`${fieldName} must be positive.`);
  }

  return integer;
}

export function parseDate(value: unknown, fieldName: string): Date {
  const source = requireString(value, fieldName);
  const date = new Date(source);
  if (Number.isNaN(date.getTime())) {
    throw new DataIntegrityError(`${fieldName} must be a valid timestamp.`);
  }

  return date;
}
