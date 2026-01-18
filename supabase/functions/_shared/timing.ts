/**
 * Shared Timing Helper for Testing Mode
 * 
 * Provides compressed timeline for testing:
 * - Week duration: 3 minutes (instead of 7 days)
 * - Grace period: 1 minute (instead of 24 hours)
 * 
 * In normal mode, uses standard timeline:
 * - Week duration: 7 days
 * - Grace period: 24 hours
 */

const TIME_ZONE = "America/New_York";

/**
 * Check if testing mode is enabled via environment variable
 * 
 * @deprecated Use getTestingMode() from mode-check.ts instead for runtime checks.
 * This constant is only kept for backward compatibility and will be removed in the future.
 */
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";

/**
 * Get week duration in milliseconds
 * - Testing mode: 3 minutes
 * - Normal mode: 7 days
 * 
 * @param isTestingMode Required: Testing mode flag (must be provided, no default)
 * @returns Week duration in milliseconds
 */
export function getWeekDurationMs(isTestingMode: boolean): number {
  return isTestingMode
    ? 3 * 60 * 1000                    // 3 minutes
    : 7 * 24 * 60 * 60 * 1000;        // 7 days
}

/**
 * Get grace period duration in milliseconds
 * - Testing mode: 1 minute
 * - Normal mode: 24 hours
 * 
 * @param isTestingMode Required: Testing mode flag (must be provided, no default)
 * @returns Grace period duration in milliseconds
 */
export function getGracePeriodMs(isTestingMode: boolean): number {
  return isTestingMode
    ? 1 * 60 * 1000                    // 1 minute
    : 24 * 60 * 60 * 1000;            // 24 hours
}

/**
 * Get date components in a specific timezone using Intl API
 */
function getDateInTimeZone(date: Date, timeZone: string): {
  year: number;
  month: number; // 0-indexed
  day: number;
  hour: number;
  dayOfWeek: number; // 0=Sunday, 1=Monday, etc.
} {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: timeZone,
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    weekday: 'short',
    hour12: false,
  });
  
  const parts = formatter.formatToParts(date);
  const partsMap: Record<string, string> = {};
  parts.forEach(part => {
    if (part.type !== 'literal') {
      partsMap[part.type] = part.value;
    }
  });
  
  const weekdayMap: Record<string, number> = {
    'Sun': 0, 'Mon': 1, 'Tue': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6
  };
  
  return {
    year: parseInt(partsMap.year, 10),
    month: parseInt(partsMap.month, 10) - 1, // Convert to 0-indexed
    day: parseInt(partsMap.day, 10),
    hour: parseInt(partsMap.hour, 10),
    dayOfWeek: weekdayMap[partsMap.weekday] ?? 0,
  };
}

/**
 * Create a Date object representing a specific date/time in ET timezone
 * Uses a simple approach: try both EST and EDT offsets, return the one that matches
 */
function createETDate(year: number, month: number, day: number, hour: number): Date {
  // Try EST first (UTC-5)
  const estDate = new Date(Date.UTC(year, month, day, hour + 5, 0, 0));
  const estComponents = getDateInTimeZone(estDate, TIME_ZONE);
  
  if (estComponents.year === year && estComponents.month === month && 
      estComponents.day === day && estComponents.hour === hour) {
    return estDate;
  }
  
  // Try EDT (UTC-4)
  const edtDate = new Date(Date.UTC(year, month, day, hour + 4, 0, 0));
  const edtComponents = getDateInTimeZone(edtDate, TIME_ZONE);
  
  if (edtComponents.year === year && edtComponents.month === month && 
      edtComponents.day === day && edtComponents.hour === hour) {
    return edtDate;
  }
  
  // Fallback: return EST (should rarely happen)
  return estDate;
}

/**
 * Calculate the next Monday 12:00 ET deadline
 * 
 * Logic:
 * - If today is Monday and before 12:00 ET, use today at 12:00 ET
 * - Otherwise, find the next Monday and set to 12:00 ET
 */
function calculateNextMondayNoonET(now: Date = new Date()): Date {
  // Get current date components in ET
  const nowET = getDateInTimeZone(now, TIME_ZONE);
  const dayOfWeek = nowET.dayOfWeek;
  const hour = nowET.hour;
  
  // Calculate days until next Monday
  let daysUntilMonday: number;
  if (dayOfWeek === 0) {
    // Sunday -> next Monday (1 day)
    daysUntilMonday = 1;
  } else if (dayOfWeek === 1) {
    // Monday
    if (hour < 12) {
      // Before noon -> use today
      daysUntilMonday = 0;
    } else {
      // After noon -> use next Monday (7 days)
      daysUntilMonday = 7;
    }
  } else {
    // Tuesday through Saturday -> next Monday
    daysUntilMonday = 8 - dayOfWeek; // Tue=6, Wed=5, Thu=4, Fri=3, Sat=2
  }
  
  // Calculate target Monday date
  const targetDate = new Date(nowET.year, nowET.month, nowET.day);
  targetDate.setDate(targetDate.getDate() + daysUntilMonday);
  
  // Create Monday 12:00 ET
  return createETDate(
    targetDate.getFullYear(),
    targetDate.getMonth(),
    targetDate.getDate(),
    12
  );
}

/**
 * Get the next deadline date
 * 
 * - Testing mode: Returns date 3 minutes from now
 * - Normal mode: Returns next Monday 12:00 ET
 * 
 * @param isTestingMode Required: Testing mode flag (must be provided, no default)
 * @param now Optional reference date (defaults to current time)
 * @returns Date object representing the deadline
 */
export function getNextDeadline(isTestingMode: boolean, now: Date = new Date()): Date {
  if (isTestingMode) {
    // Compressed timeline: 3 minutes from now
    const weekDurationMs = getWeekDurationMs(isTestingMode);
    return new Date(now.getTime() + weekDurationMs);
  }
  
  // Normal timeline: Next Monday 12:00 ET
  return calculateNextMondayNoonET(now);
}

/**
 * Get the grace period deadline (when grace period expires)
 * 
 * - Testing mode: Returns date 1 minute after the week end date
 * - Normal mode: Returns Tuesday 12:00 ET (1 day after Monday deadline)
 * 
 * @param weekEndDate The week end date (Monday deadline) - should be in ET timezone
 * @param isTestingMode Required: Testing mode flag (must be provided, no default)
 * @returns Date object representing when grace period expires
 */
export function getGraceDeadline(weekEndDate: Date, isTestingMode: boolean): Date {
  if (isTestingMode) {
    // Compressed timeline: 1 minute after deadline
    const gracePeriodMs = getGracePeriodMs(isTestingMode);
    return new Date(weekEndDate.getTime() + gracePeriodMs);
  }
  
  // Normal timeline: Tuesday 12:00 ET (1 day after Monday)
  // Get the Monday date components in ET
  const mondayET = getDateInTimeZone(weekEndDate, TIME_ZONE);
  
  // Calculate Tuesday (add 1 day to the date components)
  const tuesdayYear = mondayET.year;
  const tuesdayMonth = mondayET.month;
  const tuesdayDay = mondayET.day + 1;
  
  // Create a temporary date to handle month/year rollover
  const tempDate = new Date(tuesdayYear, tuesdayMonth, tuesdayDay);
  
  // Create Tuesday 12:00 ET
  return createETDate(
    tempDate.getFullYear(),
    tempDate.getMonth(),
    tempDate.getDate(),
    12
  );
}
