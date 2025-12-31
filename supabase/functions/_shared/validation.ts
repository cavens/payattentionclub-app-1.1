/**
 * Input validation utilities for Edge Functions
 * Prevents injection attacks and invalid data
 */

/**
 * Validate UUID format
 * @param value - Value to validate
 * @returns Valid UUID string or null
 */
export function validateUUID(value: any): string | null {
  if (typeof value !== 'string') return null;
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(value)) return null;
  return value;
}

/**
 * Validate positive number with optional max limit
 * @param value - Value to validate
 * @param max - Optional maximum value
 * @returns Valid number or null
 */
export function validatePositiveNumber(value: any, max?: number): number | null {
  const num = Number(value);
  if (isNaN(num) || num < 0) return null;
  if (max !== undefined && num > max) return null;
  return num;
}

/**
 * Validate date string
 * @param value - Value to validate
 * @returns Valid Date object or null
 */
export function validateDate(value: any): Date | null {
  if (!value) return null;
  const date = new Date(value);
  if (isNaN(date.getTime())) return null;
  return date;
}

/**
 * Validate date string in YYYY-MM-DD format
 * @param value - Value to validate
 * @returns Valid date string or null
 */
export function validateDateString(value: any): string | null {
  if (typeof value !== 'string') return null;
  const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
  if (!dateRegex.test(value)) return null;
  const date = new Date(value);
  if (isNaN(date.getTime())) return null;
  return value;
}

/**
 * Validate array of strings
 * @param value - Value to validate
 * @returns Valid string array or null
 */
export function validateStringArray(value: any): string[] | null {
  if (!Array.isArray(value)) return null;
  if (!value.every(item => typeof item === 'string')) return null;
  return value;
}

/**
 * Validate non-empty string
 * @param value - Value to validate
 * @param maxLength - Optional maximum length
 * @returns Valid string or null
 */
export function validateNonEmptyString(value: any, maxLength?: number): string | null {
  if (typeof value !== 'string') return null;
  if (value.trim().length === 0) return null;
  if (maxLength !== undefined && value.length > maxLength) return null;
  return value;
}

/**
 * Validate boolean
 * @param value - Value to validate
 * @returns Valid boolean or null
 */
export function validateBoolean(value: any): boolean | null {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    if (value.toLowerCase() === 'true') return true;
    if (value.toLowerCase() === 'false') return false;
  }
  return null;
}

