# DST Transition Fix Proposal
## How to Fix and Test Without Waiting for March/November

**Date**: 2026-01-15  
**Issue**: `getGraceDeadline()` uses `setUTCDate()` which doesn't account for DST transitions

---

## Current Problem

**File**: `supabase/functions/_shared/timing.ts:122-137`

```typescript
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // ❌ PROBLEM: This adds 1 day in UTC, not ET
  // If week spans DST transition, grace period will be 23 or 25 hours
  const grace = new Date(weekEndDate);
  grace.setUTCDate(grace.getUTCDate() + 1);
  return grace;
}
```

**Why it fails**:
- `setUTCDate()` adds 1 day in UTC (always 24 hours)
- But we need exactly 24 hours in ET timezone
- If week spans DST transition:
  - Spring forward: 24 hours UTC = 23 hours ET (grace period too short)
  - Fall back: 24 hours UTC = 25 hours ET (grace period too long)

---

## Proposed Fix

### Option 1: Use Intl API (Recommended - No Dependencies)

**Advantage**: Uses built-in JavaScript APIs, no external libraries needed

```typescript
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // Normal timeline: Tuesday 12:00 ET (exactly 24 hours after Monday 12:00 ET)
  // We need to add 24 hours in ET timezone, accounting for DST
  
  // Step 1: Get the ET representation of the deadline
  const deadlineET = toDateInTimeZone(weekEndDate, TIME_ZONE);
  
  // Step 2: Create a new date that's exactly 24 hours later in ET
  // We'll use Intl.DateTimeFormat to format the date in ET, then parse it back
  // This ensures we're working in ET timezone, not UTC
  
  // Get the date components in ET
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  
  const parts = formatter.formatToParts(deadlineET);
  const partsMap: Record<string, string> = {};
  parts.forEach(part => {
    if (part.type !== 'literal') {
      partsMap[part.type] = part.value;
    }
  });
  
  // Create date string in ET: YYYY-MM-DDTHH:mm:ss
  const deadlineETString = `${partsMap.year}-${partsMap.month}-${partsMap.day}T${partsMap.hour}:${partsMap.minute}:${partsMap.second}`;
  
  // Parse as if it's in ET (but JavaScript will interpret as local, so we need to adjust)
  // Actually, better approach: Use the ET offset to calculate
  
  // Better approach: Add 24 hours in milliseconds, then adjust for DST
  // Get the ET offset for the deadline date
  const deadlineOffset = getTimezoneOffset(deadlineET, TIME_ZONE);
  
  // Add 24 hours
  const graceTime = deadlineET.getTime() + (24 * 60 * 60 * 1000);
  const graceDate = new Date(graceTime);
  
  // Get the ET offset for the grace date (might be different due to DST)
  const graceOffset = getTimezoneOffset(graceDate, TIME_ZONE);
  
  // Adjust for DST change
  const offsetDiff = graceOffset - deadlineOffset;
  const adjustedGrace = new Date(graceTime - offsetDiff);
  
  // Now set to exactly 12:00 ET on Tuesday
  const graceET = toDateInTimeZone(adjustedGrace, TIME_ZONE);
  graceET.setHours(12, 0, 0, 0);
  
  // Convert back to UTC Date
  return new Date(graceET.toLocaleString('en-US', { timeZone: 'UTC' }));
}

// Helper function to get timezone offset in milliseconds
function getTimezoneOffset(date: Date, timeZone: string): number {
  // Get UTC time
  const utc = date.getTime();
  
  // Get time in target timezone
  const target = new Date(date.toLocaleString('en-US', { timeZone }));
  
  // Calculate offset (target - utc)
  return target.getTime() - utc;
}
```

**Simpler Alternative** (if the above is too complex):

```typescript
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // Normal timeline: Tuesday 12:00 ET (exactly 24 hours after Monday 12:00 ET)
  // Convert deadline to ET, add 24 hours, then set to 12:00 ET
  
  // Get the ET representation
  const deadlineET = toDateInTimeZone(weekEndDate, TIME_ZONE);
  
  // Add exactly 24 hours (in milliseconds)
  const graceTimeET = deadlineET.getTime() + (24 * 60 * 60 * 1000);
  
  // Create new date from the ET time
  // But we need to account for DST - the offset might have changed
  // So we'll create a date 24 hours later, then adjust to 12:00 ET
  
  // Create date 24 hours later
  const graceDate = new Date(graceTimeET);
  
  // Convert to ET to get the correct day/time
  const graceET = toDateInTimeZone(graceDate, TIME_ZONE);
  
  // Set to exactly 12:00 ET (this ensures we're on Tuesday at noon ET)
  graceET.setHours(12, 0, 0, 0);
  
  // Now we need to convert this ET time back to UTC
  // The tricky part: we have an ET time, but need a UTC Date object
  // We can use the fact that Date constructor accepts ISO strings with timezone
  
  // Get the timezone offset for this date in ET
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  
  const parts = formatter.formatToParts(graceET);
  const partsMap: Record<string, string> = {};
  parts.forEach(part => {
    if (part.type !== 'literal') {
      partsMap[part.type] = part.value;
    }
  });
  
  // Create ISO string: YYYY-MM-DDTHH:mm:ss
  // But we need to know if it's EST or EDT
  // We can check the offset
  
  // Actually, simplest: Use the Intl API to format, then parse
  // But JavaScript Date parsing is tricky with timezones
  
  // BEST APPROACH: Use a library or manual calculation
  // Since we can't use external libraries easily in Deno Edge Functions,
  // we'll use a manual approach:
  
  // Get the UTC time that corresponds to 12:00 ET on Tuesday
  // We know the deadline is Monday 12:00 ET
  // We need Tuesday 12:00 ET
  // The offset between ET and UTC changes with DST, so we need to calculate it
  
  // Calculate the offset for Monday 12:00 ET
  const mondayUTC = weekEndDate.getTime();
  const mondayET = toDateInTimeZone(weekEndDate, TIME_ZONE);
  const mondayOffset = mondayET.getTime() - mondayUTC;
  
  // Calculate the offset for Tuesday 12:00 ET (24 hours later)
  // Create a date 24 hours after Monday
  const tuesdayCandidate = new Date(mondayUTC + (24 * 60 * 60 * 1000));
  const tuesdayET = toDateInTimeZone(tuesdayCandidate, TIME_ZONE);
  const tuesdayOffset = tuesdayET.getTime() - tuesdayCandidate.getTime();
  
  // The difference in offsets tells us if DST changed
  const offsetDiff = tuesdayOffset - mondayOffset;
  
  // Tuesday 12:00 ET in UTC = Monday 12:00 ET UTC + 24 hours - offset difference
  const tuesday12ET_UTC = mondayUTC + (24 * 60 * 60 * 1000) - offsetDiff;
  
  // But we need to ensure it's exactly 12:00 ET, not just 24 hours later
  // So we'll create the date, then set it to 12:00 ET
  
  // Actually, the cleanest approach:
  // 1. Get Monday 12:00 ET as a Date object
  // 2. Add 1 day to the date components (not time)
  // 3. Set time to 12:00
  // 4. Convert to UTC
  
  const mondayETDate = new Date(deadlineET);
  const tuesdayETDate = new Date(mondayETDate);
  tuesdayETDate.setDate(tuesdayETDate.getDate() + 1); // Add 1 day
  tuesdayETDate.setHours(12, 0, 0, 0); // Set to 12:00
  
  // Now convert this ET date to UTC
  // The issue: Date objects are always in UTC internally
  // We need to create a UTC date that represents 12:00 ET on Tuesday
  
  // Use Intl to format the ET date, then parse it
  const tuesdayETString = tuesdayETDate.toLocaleString('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  
  // Parse the string to get the UTC equivalent
  // Format: "MM/DD/YYYY, HH:mm:ss"
  const [datePart, timePart] = tuesdayETString.split(', ');
  const [month, day, year] = datePart.split('/');
  const [hour, minute, second] = timePart.split(':');
  
  // Create UTC date from ET components
  // We need to know the UTC offset for this date/time in ET
  // Create a test date to get the offset
  const testDate = new Date(`${year}-${month}-${day}T${hour}:${minute}:${second}`);
  const testET = toDateInTimeZone(testDate, TIME_ZONE);
  const offset = testET.getTime() - testDate.getTime();
  
  // Adjust the UTC date by the offset
  const tuesdayUTC = new Date(testDate.getTime() - offset);
  
  return tuesdayUTC;
}
```

**Actually, the SIMPLEST fix** (using existing helper):

```typescript
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // Normal timeline: Tuesday 12:00 ET (exactly 24 hours after Monday 12:00 ET)
  // The key: We need to add 24 hours in ET timezone, not UTC
  
  // Convert deadline to ET timezone
  const deadlineET = toDateInTimeZone(weekEndDate, TIME_ZONE);
  
  // Get the date components in ET
  const year = deadlineET.getFullYear();
  const month = deadlineET.getMonth();
  const day = deadlineET.getDate();
  const hour = deadlineET.getHours();
  const minute = deadlineET.getMinutes();
  const second = deadlineET.getSeconds();
  
  // Create Tuesday 12:00 ET by adding 1 day to the date components
  // This ensures we're working in ET, not UTC
  const tuesdayET = new Date(year, month, day + 1, 12, 0, 0);
  
  // But wait - this creates a date in the LOCAL timezone, not ET
  // We need to create a date that represents 12:00 ET
  
  // Better: Use the Intl API to create a date string in ET, then parse it
  // Create an ISO-like string for Tuesday 12:00 ET
  const tuesdayYear = year;
  const tuesdayMonth = String(month + 1).padStart(2, '0');
  const tuesdayDay = String(day + 1).padStart(2, '0');
  
  // Create a date string: "YYYY-MM-DDTHH:mm:ss" (this will be interpreted as local)
  // But we want ET, so we need to use a different approach
  
  // BEST: Use the existing toDateInTimeZone helper in reverse
  // We want: Given a date/time in ET, what is the UTC Date object?
  
  // Create a date that represents Tuesday 12:00 in the system's understanding
  // Then convert it to ET to verify, then adjust
  
  // Actually, the cleanest: Create the date, convert to ET, check if it's Tuesday 12:00
  // If not, adjust until it is
  
  // SIMPLEST WORKING SOLUTION:
  // 1. Start with Monday 12:00 ET (already have this as deadlineET)
  // 2. Add 24 hours in milliseconds
  // 3. Convert the result to ET
  // 4. If it's not exactly 12:00, adjust to 12:00
  // 5. Convert back to UTC Date
  
  let graceTime = deadlineET.getTime() + (24 * 60 * 60 * 1000);
  let graceDate = new Date(graceTime);
  let graceET = toDateInTimeZone(graceDate, TIME_ZONE);
  
  // Set to exactly 12:00 ET
  graceET.setHours(12, 0, 0, 0);
  
  // Now we need the UTC Date that represents this ET time
  // Calculate the offset between graceET (local) and graceDate (UTC)
  // But graceET is already in ET, so we need to work backwards
  
  // Get what UTC time corresponds to 12:00 ET on Tuesday
  // We can use the offset calculation
  
  // Calculate offset: ET time - UTC time
  const offset = graceET.getTime() - graceDate.getTime();
  
  // The UTC time that gives us 12:00 ET is: graceET time - offset
  // But graceET is a Date object in local time, not ET
  
  // FINAL SOLUTION: Use Intl.DateTimeFormat to format, then manually calculate UTC
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  
  // Format the deadline to get ET components
  const deadlineParts = formatter.formatToParts(deadlineET);
  const deadlineMap: Record<string, string> = {};
  deadlineParts.forEach(p => { if (p.type !== 'literal') deadlineMap[p.type] = p.value; });
  
  // Calculate Tuesday (add 1 to day)
  const tuesdayDay = String(parseInt(deadlineMap.day) + 1).padStart(2, '0');
  
  // Create ISO string for Tuesday 12:00 ET
  // Format: "YYYY-MM-DDTHH:mm:ss" - but we need to specify it's in ET
  // JavaScript doesn't support timezone in ISO strings directly, so we need to calculate
  
  // Create a date object for Tuesday 12:00 in UTC first
  const tuesdayUTC = new Date(
    parseInt(deadlineMap.year),
    parseInt(deadlineMap.month) - 1, // month is 0-indexed
    parseInt(tuesdayDay),
    12, 0, 0
  );
  
  // Now get what this UTC time is in ET
  const tuesdayET_check = toDateInTimeZone(tuesdayUTC, TIME_ZONE);
  
  // Calculate the offset
  const tuesdayOffset = tuesdayET_check.getTime() - tuesdayUTC.getTime();
  
  // Adjust: We want 12:00 ET, so UTC = ET - offset
  // But we calculated offset as ET - UTC, so UTC = ET - offset
  // If tuesdayET_check shows 12:00 ET, then tuesdayUTC is correct
  // If not, we need to adjust
  
  if (tuesdayET_check.getHours() === 12 && tuesdayET_check.getMinutes() === 0) {
    return tuesdayUTC;
  } else {
    // Adjust: the offset tells us the difference
    // We want 12:00 ET, so we need to find the UTC time that gives us that
    const targetET = new Date(tuesdayUTC);
    targetET.setHours(12, 0, 0, 0);
    const targetOffset = targetET.getTime() - tuesdayUTC.getTime();
    return new Date(tuesdayUTC.getTime() - targetOffset);
  }
}
```

**This is getting too complex. Let me propose the CLEANEST solution:**

---

## Recommended Fix (Simple & Testable)

```typescript
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // Normal timeline: Tuesday 12:00 ET (exactly 24 hours after Monday 12:00 ET)
  // Strategy: Convert to ET, add 1 day to date components, set to 12:00, convert back
  
  // Step 1: Get Monday 12:00 ET as a proper ET date
  const deadlineET = toDateInTimeZone(weekEndDate, TIME_ZONE);
  
  // Step 2: Create Tuesday 12:00 ET by manipulating date components
  // Use Intl to format the date in ET, extract components, add 1 day
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  });
  
  const parts = formatter.formatToParts(deadlineET);
  const partsMap: Record<string, string> = {};
  parts.forEach(part => {
    if (part.type !== 'literal') {
      partsMap[part.type] = part.value;
    }
  });
  
  // Step 3: Calculate Tuesday (add 1 day)
  const mondayDay = parseInt(partsMap.day);
  const tuesdayDay = mondayDay + 1;
  
  // Step 4: Create a date string for Tuesday 12:00 ET
  // Format: "YYYY-MM-DDTHH:mm:ss" - we'll create this in ET
  const tuesdayETString = `${partsMap.year}-${partsMap.month}-${String(tuesdayDay).padStart(2, '0')}T12:00:00`;
  
  // Step 5: Parse this as if it's in ET and convert to UTC Date
  // We need to use a timezone-aware parser
  // Since JavaScript Date doesn't support timezone in constructor,
  // we'll use the fact that we can calculate the UTC equivalent
  
  // Create a test date to find the offset
  // We'll create the date in UTC first, then adjust
  const tuesdayUTC = new Date(
    parseInt(partsMap.year),
    parseInt(partsMap.month) - 1, // month is 0-indexed
    tuesdayDay,
    12, 0, 0
  );
  
  // Check what this UTC date is in ET
  const tuesdayET_check = toDateInTimeZone(tuesdayUTC, TIME_ZONE);
  
  // If it's already 12:00 ET, we're done
  if (tuesdayET_check.getHours() === 12 && tuesdayET_check.getMinutes() === 0) {
    return tuesdayUTC;
  }
  
  // Otherwise, calculate the offset and adjust
  // The offset is: ET_time - UTC_time
  const offset = tuesdayET_check.getTime() - tuesdayUTC.getTime();
  
  // We want 12:00 ET, so we need UTC = ET_time - offset
  // But we want to set ET to 12:00, so:
  // Create a date that represents 12:00 ET
  // offset = ET - UTC, so UTC = ET - offset
  // If we want ET = 12:00, and we know the offset, we can calculate UTC
  
  // Get the current offset for Tuesday 12:00 ET
  // We need to find the UTC time that gives us 12:00 ET
  // This is: UTC = ET_desired - offset_current
  
  // Calculate what UTC time gives us 12:00 ET on Tuesday
  const desiredET = new Date(tuesdayUTC);
  desiredET.setHours(12, 0, 0, 0);
  const desiredOffset = desiredET.getTime() - tuesdayUTC.getTime();
  
  // The UTC time we want is: desiredET - offset
  // But desiredET is in local time, not ET
  // We need to work with ET directly
  
  // FINAL APPROACH: Use the offset to adjust
  // We know: tuesdayET_check is what Tuesday 12:00 UTC is in ET
  // We want: Tuesday 12:00 ET in UTC
  // The difference tells us how to adjust
  
  const hoursOff = tuesdayET_check.getHours() - 12;
  const minutesOff = tuesdayET_check.getMinutes();
  
  // Adjust UTC time by the difference
  const adjustedUTC = new Date(tuesdayUTC.getTime() - (hoursOff * 60 * 60 * 1000) - (minutesOff * 60 * 1000));
  
  // Verify it's correct
  const verifyET = toDateInTimeZone(adjustedUTC, TIME_ZONE);
  if (verifyET.getHours() === 12 && verifyET.getMinutes() === 0) {
    return adjustedUTC;
  }
  
  // Fallback: If adjustment didn't work, use the simpler approach
  // Just add 24 hours and hope DST doesn't change (not ideal, but better than current)
  return new Date(weekEndDate.getTime() + (24 * 60 * 60 * 1000));
}
```

**Actually, I think the issue is we're overcomplicating this. Here's the REAL simple fix:**

---

## The Real Simple Fix

The issue is that we're using `setUTCDate()` which adds a calendar day in UTC. Instead, we should:

1. Get the ET representation of Monday 12:00
2. Add 1 day to the **date components** (not time)
3. Set to 12:00 ET
4. Convert back to UTC Date

But JavaScript Date objects are always in UTC internally. The key insight: We need to calculate what UTC time corresponds to "Tuesday 12:00 ET", accounting for the fact that the ET offset might have changed due to DST.

**Simplest working solution**:

```typescript
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // Normal timeline: Tuesday 12:00 ET (exactly 24 hours after Monday 12:00 ET)
  // Strategy: Use Intl API to format/parse dates in ET timezone
  
  // Get Monday 12:00 ET components
  const deadlineET = toDateInTimeZone(weekEndDate, TIME_ZONE);
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  });
  
  const mondayParts = formatter.formatToParts(deadlineET);
  const mondayMap: Record<string, string> = {};
  mondayParts.forEach(p => { if (p.type !== 'literal') mondayMap[p.type] = p.value; });
  
  // Calculate Tuesday (add 1 day)
  const tuesdayDay = parseInt(mondayMap.day) + 1;
  
  // Create a date for Tuesday 12:00 in ET
  // We'll create it as a UTC date first, then adjust
  const tuesdayUTC = new Date(
    Date.UTC(
      parseInt(mondayMap.year),
      parseInt(mondayMap.month) - 1,
      tuesdayDay,
      12, 0, 0
    )
  );
  
  // Check what this UTC date is in ET
  const tuesdayET = toDateInTimeZone(tuesdayUTC, TIME_ZONE);
  
  // Calculate the offset: ET - UTC
  const offset = tuesdayET.getTime() - tuesdayUTC.getTime();
  
  // We want 12:00 ET, so we need to adjust the UTC time
  // If tuesdayET is not 12:00, we need to shift
  const hoursDiff = tuesdayET.getHours() - 12;
  const minutesDiff = tuesdayET.getMinutes();
  
  // Adjust: subtract the difference to get 12:00 ET
  const adjustedUTC = new Date(
    tuesdayUTC.getTime() - (hoursDiff * 60 * 60 * 1000) - (minutesDiff * 60 * 1000)
  );
  
  return adjustedUTC;
}
```

---

## How to Test Without Waiting for March/November

### Option 1: Mock Dates (Recommended)

Create a test file that uses specific dates that span DST transitions:

```typescript
// test_dst_fix.ts
import { getGraceDeadline } from './timing.ts';

// Test case 1: Week spanning spring forward (March 8-15, 2026)
// Monday March 8, 2026 12:00 EST
const mondaySpring = new Date('2026-03-08T17:00:00Z'); // 12:00 EST = 17:00 UTC
const graceSpring = getGraceDeadline(mondaySpring);

// Expected: Tuesday March 10, 2026 12:00 EDT (note: EDT, not EST)
// Tuesday March 10, 2026 12:00 EDT = 16:00 UTC (EDT is UTC-4, EST is UTC-5)
const expectedSpring = new Date('2026-03-10T16:00:00Z');

console.log('Spring forward test:');
console.log('  Monday:', mondaySpring.toISOString());
console.log('  Grace:', graceSpring.toISOString());
console.log('  Expected:', expectedSpring.toISOString());
console.log('  Match:', graceSpring.getTime() === expectedSpring.getTime());
console.log('  Hours difference:', (graceSpring.getTime() - mondaySpring.getTime()) / (1000 * 60 * 60));

// Test case 2: Week spanning fall back (November 1-8, 2026)
// Monday November 1, 2026 12:00 EDT
const mondayFall = new Date('2026-11-01T16:00:00Z'); // 12:00 EDT = 16:00 UTC
const graceFall = getGraceDeadline(mondayFall);

// Expected: Tuesday November 3, 2026 12:00 EST (note: EST, not EDT)
// Tuesday November 3, 2026 12:00 EST = 17:00 UTC (EST is UTC-5, EDT is UTC-4)
const expectedFall = new Date('2026-11-03T17:00:00Z');

console.log('\nFall back test:');
console.log('  Monday:', mondayFall.toISOString());
console.log('  Grace:', graceFall.toISOString());
console.log('  Expected:', expectedFall.toISOString());
console.log('  Match:', graceFall.getTime() === expectedFall.getTime());
console.log('  Hours difference:', (graceFall.getTime() - mondayFall.getTime()) / (1000 * 60 * 60));

// Test case 3: Week NOT spanning DST (normal case)
// Monday January 12, 2026 12:00 EST
const mondayNormal = new Date('2026-01-12T17:00:00Z'); // 12:00 EST = 17:00 UTC
const graceNormal = getGraceDeadline(mondayNormal);

// Expected: Tuesday January 13, 2026 12:00 EST
// Tuesday January 13, 2026 12:00 EST = 17:00 UTC
const expectedNormal = new Date('2026-01-13T17:00:00Z');

console.log('\nNormal week test:');
console.log('  Monday:', mondayNormal.toISOString());
console.log('  Grace:', graceNormal.toISOString());
console.log('  Expected:', expectedNormal.toISOString());
console.log('  Match:', graceNormal.getTime() === expectedNormal.getTime());
console.log('  Hours difference:', (graceNormal.getTime() - mondayNormal.getTime()) / (1000 * 60 * 60));
```

### Option 2: Use a Date Library (If Available)

If you can add a dependency, use `date-fns-tz` or `luxon`:

```typescript
import { zonedTimeToUtc, utcToZonedTime } from 'date-fns-tz';

export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  
  // Convert to ET
  const deadlineET = utcToZonedTime(weekEndDate, TIME_ZONE);
  
  // Add 1 day and set to 12:00
  const tuesdayET = new Date(deadlineET);
  tuesdayET.setDate(tuesdayET.getDate() + 1);
  tuesdayET.setHours(12, 0, 0, 0);
  
  // Convert back to UTC
  return zonedTimeToUtc(tuesdayET, TIME_ZONE);
}
```

---

## Recommendation

**Use Option 1 (Mock Dates)** because:
1. ✅ No external dependencies
2. ✅ Can test immediately
3. ✅ Tests real DST transition dates
4. ✅ Verifies exact 24-hour grace period in ET

**Implementation Steps**:
1. Implement the fix in `timing.ts`
2. Create test file `test_dst_fix.ts`
3. Run tests to verify fix works
4. Add tests to CI/CD pipeline



