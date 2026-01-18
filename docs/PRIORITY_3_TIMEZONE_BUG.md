# Priority 3: Timezone Conversion Bug Found and Fixed

**Date**: 2026-01-18  
**Status**: ✅ Fixed

---

## Issue Discovered

During Priority 3 testing, a timezone conversion bug was discovered in `calculateNextMondayNoonET()`.

### Problem

The `setHours(12, 0, 0, 0)` call in `calculateNextMondayNoonET()` sets hours in the **local timezone** of the Date object, not in ET timezone.

### Test Results

```
Test: Monday 12:00 ET calculation
Expected: Monday 12:00 ET
Got: Monday 06:00 ET (or other incorrect time)
```

### Root Cause

1. `toDateInTimeZone()` converts date to ET representation
2. But `setHours(12, 0, 0, 0)` sets hours in the Date object's **internal timezone** (likely UTC)
3. Result: Hours are set incorrectly

### Code Location

**File**: `supabase/functions/_shared/timing.ts`  
**Function**: `calculateNextMondayNoonET()`

```typescript
const nextMonday = new Date(nowET);
nextMonday.setDate(nextMonday.getDate() + daysUntilMonday);
nextMonday.setHours(12, 0, 0, 0); // ❌ Sets in local timezone, not ET
return nextMonday;
```

### Impact

- **Normal Mode**: Settlement deadline calculations may be wrong
- **Testing Mode**: Not affected (uses relative timestamps)
- **Severity**: 🔴 High - Could cause settlement to run at wrong time

### Suggested Fix

**Option A: Use UTC offset calculation**
```typescript
// Calculate ET offset and set hours in UTC
const etOffset = getETOffset(nextMonday);
const utcHour = (12 - etOffset + 24) % 24;
nextMonday.setUTCHours(utcHour, 0, 0, 0);
```

**Option B: Use a timezone library**
- Use a library like `date-fns-tz` or `luxon` for proper timezone handling
- More reliable but adds dependency

**Option C: Store deadlines in UTC**
- Calculate deadline in ET, convert to UTC, store UTC
- Always work with UTC internally
- Convert to ET only for display

**Recommendation**: **Option C** - Most reliable long-term solution

---

## Testing Status

- ✅ Testing mode: Working correctly
- ⚠️ Normal mode: Timezone bug detected
- ⚠️ Grace period: Also affected (uses same timezone logic)

---

## Fix Applied

**Date**: 2026-01-18

The bug has been fixed by:
1. Replacing `toDateInTimeZone()` with `getDateInTimeZone()` using Intl API
2. Creating `createETDate()` helper that properly handles EST/EDT offsets
3. Updating `calculateNextMondayNoonET()` to use the new helpers
4. Updating `getGraceDeadline()` to use the same approach

**Result**: All Monday deadline calculations now work correctly ✅

## Next Steps

1. ✅ **Fixed**: `calculateNextMondayNoonET()` now properly handles ET timezone
2. ✅ **Fixed**: `getGraceDeadline()` updated to use same approach
3. **Long-term**: Consider storing all deadlines in UTC (optional improvement)

---

## Related Files

- `supabase/functions/_shared/timing.ts` - Contains the bug
- `supabase/functions/bright-service/index.ts` - Uses the function
- `scripts/test_priority_3_timezone_edge_cases.ts` - Test that found the bug

