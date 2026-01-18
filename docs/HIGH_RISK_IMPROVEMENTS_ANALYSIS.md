# High Risk Improvements Analysis

**Date**: 2026-01-18  
**Purpose**: Analyze high risks and suggest improvements (no changes made)

---

## 🔴 CRITICAL RISK 1: Module-Level Constants Stale After Mode Change

### Current Problem

**File**: `supabase/functions/_shared/timing.ts`

```typescript
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
export const WEEK_DURATION_MS = TESTING_MODE 
  ? 3 * 60 * 1000                    // 3 minutes
  : 7 * 24 * 60 * 60 * 1000;        // 7 days
export const GRACE_PERIOD_MS = TESTING_MODE
  ? 1 * 60 * 1000                    // 1 minute
  : 24 * 60 * 60 * 1000;            // 24 hours
```

**Issue**:
- These constants are evaluated **once** when the Edge Function module loads
- If `TESTING_MODE` env var changes, constants don't update until function redeploys or cold starts
- Functions that use these constants directly get **stale values**

**Where Used**:
- `preview-service/index.ts` - Uses `TESTING_MODE` constant directly
- `getNextDeadline()` - Uses `WEEK_DURATION_MS` constant
- Any function that imports these constants

**Impact**:
- Mode toggle updates `app_config` and env var
- But Edge Functions still use old constants until redeploy
- **Result**: Wrong timing calculations for hours/days until cold start

### Suggested Improvement

**Option A: Remove Module-Level Constants (Recommended)**
- Remove `WEEK_DURATION_MS` and `GRACE_PERIOD_MS` constants
- Always use functions: `getGracePeriodMs(isTestingMode)` and `getGraceDeadline(date, isTestingMode)`
- Functions must pass `isTestingMode` parameter (from database check)

**Option B: Add Runtime Validation**
- Keep constants for backward compatibility
- Add validation that warns if constants don't match database
- Log warning when mismatch detected

**Option C: Force Cold Start After Mode Change**
- After mode toggle, trigger a dummy Edge Function call to force cold start
- Ensures new constants are loaded
- **Downside**: Adds latency, not guaranteed

**Recommendation**: **Option A** - Most reliable, eliminates stale constant risk

---

## 🔴 CRITICAL RISK 2: Inconsistent Mode Checking

### Current Problem

**Mixed Patterns**:

1. **Functions that check database at runtime** (✅ Good):
   - `bright-service/index.ts` - Checks `app_config`, falls back to env var
   - `super-service/index.ts` - Checks `app_config`, falls back to env var
   - `testing-command-runner/index.ts` - Checks `app_config`, falls back to env var

2. **Functions that only use constant** (❌ Risky):
   - `preview-service/index.ts` - Only uses `TESTING_MODE` constant
   - `getNextDeadline()` - Uses `TESTING_MODE` constant directly

**Issue**:
- `preview-service` doesn't check database
- If env var is wrong but `app_config` is correct, `preview-service` uses wrong mode
- `getNextDeadline()` called without `isTestingMode` parameter uses stale constant

**Impact**:
- Preview deadline calculations can be wrong
- Inconsistent behavior across functions

### Suggested Improvement

**Standardize Mode Checking Pattern**:

1. **Create shared helper function**:
   ```typescript
   // _shared/mode-check.ts
   export async function getTestingMode(supabase: SupabaseClient): Promise<boolean> {
     // Check database first (primary source)
     const { data: config } = await supabase
       .from('app_config')
       .select('value')
       .eq('key', 'testing_mode')
       .single();
     
     if (config?.value === 'true') return true;
     
     // Fallback to env var
     return Deno.env.get("TESTING_MODE") === "true";
   }
   ```

2. **Update all functions to use helper**:
   - `preview-service/index.ts` - Add database check
   - `getNextDeadline()` - Always require `isTestingMode` parameter
   - Remove direct `TESTING_MODE` constant usage

3. **Add validation logging**:
   - Log when database and env var don't match
   - Alert on mode mismatch

**Recommendation**: Standardize on database-first pattern across all functions

---

## 🔴 CRITICAL RISK 3: Time Zone Calculation Edge Cases

### Current Problem

**File**: `supabase/functions/_shared/timing.ts` - `calculateNextMondayNoonET()`

**Issue**:
- Normal mode must calculate "previous Monday 12:00 ET" from any timezone
- Edge cases:
  - Commitment created Monday 11:59 AM ET → Should use today
  - Commitment created Monday 12:01 PM ET → Should use next Monday
  - Commitment created Sunday 11:59 PM ET → Should use tomorrow (Monday)
  - Timezone conversion errors

**Current Logic**:
```typescript
if (dayOfWeek === 1) { // Monday
  if (hour < 12) {
    daysUntilMonday = 0; // Use today
  } else {
    daysUntilMonday = 7; // Use next Monday
  }
}
```

**Potential Issues**:
- What if commitment created at exactly 12:00:00 ET? (boundary case)
- What if timezone conversion is off by 1 hour? (DST issues)
- What if server timezone differs from ET?

### Suggested Improvement

**Option A: Add Comprehensive Tests**
- Test all edge cases:
  - Monday 11:59:59 AM ET
  - Monday 12:00:00 PM ET
  - Monday 12:00:01 PM ET
  - Sunday 11:59:59 PM ET
  - Monday 12:00:00 AM ET
- Test with different server timezones
- Test DST transitions

**Option B: Use UTC for All Calculations**
- Store all deadlines in UTC
- Convert to ET only for display
- Eliminates timezone conversion errors

**Option C: Add Validation**
- After calculating Monday, verify it's correct
- Log warnings if calculation seems wrong
- Add sanity checks (e.g., "Monday should be between X and Y")

**Recommendation**: **Option A + Option C** - Test thoroughly, add validation

---

## 🟡 HIGH RISK 4: Grace Period Calculation (24 Hours)

### Current Problem

**File**: `supabase/functions/_shared/timing.ts` - `getGraceDeadline()`

**Normal Mode Logic**:
```typescript
const grace = new Date(weekEndDate);
grace.setUTCDate(grace.getUTCDate() + 1);
```

**Issue**:
- Adds 1 day to Monday 12:00 ET
- But what if DST transition happens during that 24 hours?
- What if the calculation is off by milliseconds?
- 24-hour window is large, timing errors more likely

**Impact**:
- User syncs 23 hours 59 minutes after deadline → Should be in grace
- User syncs 24 hours 1 minute after deadline → Should trigger reconciliation
- Small timing errors can cause wrong behavior

### Suggested Improvement

**Option A: Use Precise Timestamp Calculation**
```typescript
// Instead of adding 1 day, add exactly 24 hours
const grace = new Date(weekEndDate.getTime() + 24 * 60 * 60 * 1000);
```

**Option B: Add Buffer Zone**
- Grace period: 24 hours ± 5 minutes buffer
- Prevents edge case timing errors
- Logs warnings for near-boundary cases

**Option C: Store Grace Deadline Explicitly**
- Calculate grace deadline when commitment is created
- Store in database (like `week_end_timestamp`)
- Eliminates runtime calculation errors

**Recommendation**: **Option A + Option C** - Use precise calculation, store explicitly

---

## 🟡 HIGH RISK 5: Batch Processing Without Transaction Safety

### Current Problem

**File**: `supabase/functions/bright-service/index.ts` - Settlement processing

**Issue**:
- Normal mode processes many commitments in one batch
- If settlement fails partway through:
  - Some users charged ✅
  - Some users not charged ❌
  - Database in inconsistent state

**Current Code**:
- Processes candidates in loop
- Each charge is separate Stripe call
- No transaction wrapping multiple charges

**Impact**:
- Partial settlement failures
- Some users charged, others not
- Hard to recover from partial state

### Suggested Improvement

**Option A: Add Idempotency Keys**
- Each settlement attempt has unique idempotency key
- Stripe prevents duplicate charges
- Can safely retry failed settlements

**Option B: Process in Smaller Batches**
- Process 10 commitments at a time
- If batch fails, only 10 affected (not hundreds)
- Easier to retry

**Option C: Add Settlement Status Tracking**
- Track which commitments were attempted
- Track which succeeded/failed
- Can resume from last successful point

**Option D: Use Database Transactions**
- Wrap settlement updates in transaction
- If Stripe charge fails, rollback database updates
- **Challenge**: Stripe calls are external, can't rollback

**Recommendation**: **Option A + Option C** - Idempotency prevents duplicates, tracking enables recovery

---

## 🟡 HIGH RISK 6: Configuration Sync Window

### Current Problem

**Mode Toggle Process**:
1. Update `app_config.testing_mode` ✅
2. Call `update-secret` to update `TESTING_MODE` env var ✅
3. But: Edge Functions still have old constants in memory ❌

**Window of Inconsistency**:
- Database updated ✅
- Env var updated ✅
- But Edge Functions using stale constants until cold start
- **Duration**: Can be hours if function stays warm

### Suggested Improvement

**Option A: Force Cold Start After Toggle**
- After mode toggle, make a dummy call to each Edge Function
- Forces reload of module constants
- **Downside**: Adds latency

**Option B: Remove Dependency on Constants**
- Don't use module-level constants
- Always check database at runtime
- **Best solution**: Eliminates stale constant problem

**Option C: Add Mode Validation Endpoint**
- Create endpoint that checks mode consistency
- Returns warnings if mismatch detected
- Can be called after mode toggle to verify

**Recommendation**: **Option B** - Most reliable, eliminates the problem entirely

---

## Summary of Recommendations

### Priority 1 (Critical - Fix First)
1. ✅ **Remove module-level constants** - Use functions with `isTestingMode` parameter
2. ✅ **Standardize mode checking** - All functions check database first
3. ✅ **Add timezone edge case tests** - Test all boundary conditions

### Priority 2 (High - Fix Soon)
4. ✅ **Improve grace period calculation** - Use precise timestamps, store explicitly
5. ✅ **Add idempotency to settlement** - Prevent duplicate charges
6. ✅ **Add settlement status tracking** - Enable recovery from partial failures

### Priority 3 (Medium - Monitor)
7. ✅ **Add mode validation endpoint** - Detect configuration mismatches
8. ✅ **Add comprehensive logging** - Track mode changes and inconsistencies
9. ✅ **Monitor for stuck commitments** - Alert on settlement failures

---

## Implementation Order

1. **Phase 1**: Standardize mode checking (Risk 2)
   - Create shared helper function
   - Update all functions to use it
   - Remove direct constant usage

2. **Phase 2**: Remove module-level constants (Risk 1)
   - Remove `WEEK_DURATION_MS` and `GRACE_PERIOD_MS`
   - Update all callers to use functions
   - Test thoroughly

3. **Phase 3**: Add timezone tests (Risk 3)
   - Create comprehensive test suite
   - Test all edge cases
   - Fix any issues found

4. **Phase 4**: Improve settlement safety (Risk 5)
   - Add idempotency keys
   - Add status tracking
   - Test batch processing

5. **Phase 5**: Improve grace period (Risk 4)
   - Use precise calculations
   - Store deadlines explicitly
   - Test edge cases

---

## Testing Strategy

### Before Implementing Changes
1. Create test suite for all edge cases
2. Test mode transitions thoroughly
3. Test timezone calculations
4. Test batch processing with failures

### After Implementing Changes
1. Run full test suite
2. Test mode toggle end-to-end
3. Monitor for configuration mismatches
4. Verify no stale constants remain

---

## Monitoring Recommendations

1. **Mode Consistency Check**
   - Run `rpc_validate_mode_consistency()` daily
   - Alert if `valid: false`
   - Alert if database and env var don't match

2. **Settlement Monitoring**
   - Log settlement execution time
   - Monitor for partial failures
   - Track stuck commitments

3. **Configuration Change Logging**
   - Log all mode toggles
   - Log when constants are loaded
   - Track cold starts

---

## Notes

- **No changes made** - This is analysis and recommendations only
- All suggestions are backward compatible (can be implemented incrementally)
- Priority order based on risk level and implementation complexity
- Testing is critical before implementing any changes

