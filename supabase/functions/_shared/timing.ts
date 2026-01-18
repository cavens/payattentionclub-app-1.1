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
 */
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";

/**
 * Week duration in milliseconds
 * - Testing mode: 3 minutes
 * - Normal mode: 7 days
 */
export const WEEK_DURATION_MS = TESTING_MODE 
  ? 3 * 60 * 1000                    // 3 minutes
  : 7 * 24 * 60 * 60 * 1000;        // 7 days

/**
 * Grace period duration in milliseconds
 * - Testing mode: 1 minute
 * - Normal mode: 24 hours
 * 
 * Note: This constant is calculated at module load time.
 * For dynamic testing mode, use getGraceDeadline() with isTestingMode parameter.
 */
export const GRACE_PERIOD_MS = TESTING_MODE
  ? 1 * 60 * 1000                    // 1 minute
  : 24 * 60 * 60 * 1000;            // 24 hours

/**
 * Get grace period duration in milliseconds
 * - Testing mode: 1 minute
 * - Normal mode: 24 hours
 * 
 * @param isTestingMode Optional: Override testing mode check. If not provided, uses TESTING_MODE constant
 * @returns Grace period duration in milliseconds
 */
export function getGracePeriodMs(isTestingMode?: boolean): number {
  const useTestingMode = isTestingMode ?? TESTING_MODE;
  return useTestingMode
    ? 1 * 60 * 1000                    // 1 minute
    : 24 * 60 * 60 * 1000;            // 24 hours
}

/**
 * Convert a date to a specific timezone
 */
function toDateInTimeZone(date: Date, timeZone: string): Date {
  return new Date(date.toLocaleString("en-US", { timeZone }));
}

/**
 * Calculate the next Monday 12:00 ET deadline
 * 
 * Logic:
 * - If today is Monday and before 12:00 ET, use today at 12:00 ET
 * - Otherwise, find the next Monday and set to 12:00 ET
 */
function calculateNextMondayNoonET(now: Date = new Date()): Date {
  const nowET = toDateInTimeZone(now, TIME_ZONE);
  const dayOfWeek = nowET.getDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  const hour = nowET.getHours();
  
  // Calculate days until next Monday
  // dayOfWeek: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
  // daysUntilMonday: 
  //   Sun (0) -> 1 day
  //   Mon (1) -> 0 days (if before noon) or 7 days (if after noon)
  //   Tue (2) -> 6 days
  //   Wed (3) -> 5 days
  //   Thu (4) -> 4 days
  //   Fri (5) -> 3 days
  //   Sat (6) -> 2 days
  
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
    // Formula: (8 - dayOfWeek) % 7, but we want next Monday, so:
    daysUntilMonday = 8 - dayOfWeek; // Tue=6, Wed=5, Thu=4, Fri=3, Sat=2
  }
  
  const nextMonday = new Date(nowET);
  nextMonday.setDate(nextMonday.getDate() + daysUntilMonday);
  nextMonday.setHours(12, 0, 0, 0); // Sets hours, minutes, seconds, milliseconds all at once
  
  return nextMonday;
}

/**
 * Get the next deadline date
 * 
 * - Testing mode: Returns date 3 minutes from now
 * - Normal mode: Returns next Monday 12:00 ET
 * 
 * @param now Optional reference date (defaults to current time)
 * @returns Date object representing the deadline
 */
export function getNextDeadline(now: Date = new Date()): Date {
  if (TESTING_MODE) {
    // Compressed timeline: 3 minutes from now
    return new Date(now.getTime() + WEEK_DURATION_MS);
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
 * @param isTestingMode Optional: Override testing mode check. If not provided, uses TESTING_MODE constant (backward compatible)
 * @returns Date object representing when grace period expires
 */
export function getGraceDeadline(weekEndDate: Date, isTestingMode?: boolean): Date {
  // Use provided isTestingMode parameter, or fall back to TESTING_MODE constant for backward compatibility
  const useTestingMode = isTestingMode ?? TESTING_MODE;
  
  if (useTestingMode) {
    // Compressed timeline: 1 minute after deadline
    // Use dynamic function to get correct grace period duration
    const gracePeriodMs = getGracePeriodMs(useTestingMode);
    return new Date(weekEndDate.getTime() + gracePeriodMs);
  }
  
  // Normal timeline: Tuesday 12:00 ET (1 day after Monday)
  // weekEndDate should already be in ET timezone (Monday 12:00 ET)
  // We need to add 1 day while preserving the ET timezone
  // Since Date objects store time in UTC internally, we need to work with the ET representation
  const grace = new Date(weekEndDate);
  grace.setUTCDate(grace.getUTCDate() + 1);
  // Preserve the time (12:00 ET) - the hours/minutes are already correct for ET
  // No need to set hours again since we're just adding a day
  return grace;
}

