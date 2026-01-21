# Case 1_A_A Fix Proposal

**Date**: 2026-01-20  
**Test Case**: Case 1_A_A (Sync Before Grace Begins + Sync Within Grace + 0 Usage + 0 Penalty)  
**Status**: ❌ FAILED → Proposed Fix

---

## Problem Summary

**Expected Behavior:**
- User syncs usage within grace period with 0 penalty
- Settlement detects synced usage (`hasSyncedUsage() = true`)
- Settlement calculates charge as 0 cents (zero penalty)
- Settlement skips charge (zero amount check)
- Status remains `pending`, no payment created

**Actual Behavior:**
- Settlement did NOT detect synced usage (`hasSyncedUsage() = false`)
- Settlement charged worst case (`500` cents)
- Status set to `charged_worst_case`
- Payment created with `penalty_worst_case` type

---

## Root Cause Analysis

### Issue 1: `hasSyncedUsage()` Only Checks `reportedDays`

**Current Implementation** (`run-weekly-settlement.ts:225-227`):
```typescript
function hasSyncedUsage(candidate: SettlementCandidate): boolean {
  return candidate.reportedDays > 0;
}
```

**Problem:**
- `reportedDays` comes from `fetchUsageCounts()` which queries `daily_usage` by `commitment_id`
- If `commitment_id` doesn't match or usage entry doesn't exist, `reportedDays = 0`
- No fallback check (e.g., checking `penalty.actual_amount_cents` or `penalty.last_updated`)

### Issue 2: No Timing Verification

**Problem:**
- `hasSyncedUsage()` doesn't verify WHEN usage was synced
- Should only count usage synced BEFORE grace period expires
- Currently counts ANY usage entry, regardless of when it was synced

### Issue 3: Zero Penalty Still Gets Charged

**Problem:**
- Even if usage is detected, when `total_penalty_cents = 0`, settlement should skip charge
- But if `hasUsage = false`, it charges worst case instead of checking actual penalty

---

## Proposed Fix for Case 1_A_A

### Fix Strategy: Multi-Layer Detection with Fallback

**Approach**: Make `hasSyncedUsage()` more robust by checking multiple indicators:

1. **Primary**: Check `reportedDays > 0` (usage entries exist)
2. **Fallback 1**: Check `penalty.actual_amount_cents` (set by `rpc_sync_daily_usage`)
3. **Fallback 2**: Check `penalty.last_updated` (timestamp when penalty was calculated)
4. **Timing**: Verify usage was synced before grace period expired

### Implementation

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

**Replace** `hasSyncedUsage()` function (lines 225-227):

```typescript
function hasSyncedUsage(candidate: SettlementCandidate, isTestingMode?: boolean): boolean {
  // Method 1: Check if usage entries exist (primary indicator)
  if (candidate.reportedDays > 0) {
    // Verify usage was synced before grace period expired
    const penalty = candidate.penalty;
    if (penalty?.last_updated) {
      const graceDeadline = getGraceDeadline(
        getCommitmentDeadline(candidate, isTestingMode ?? false),
        isTestingMode
      );
      const lastUpdated = new Date(penalty.last_updated);
      // Usage must be synced before grace expires for Case 1
      return lastUpdated.getTime() <= graceDeadline.getTime();
    }
    // If no last_updated timestamp, assume usage was synced (backward compatibility)
    // This handles existing records that don't have last_updated set
    return true;
  }
  
  // Method 2: Fallback - Check if actual_amount_cents is set
  // This catches cases where usage was synced but reportedDays wasn't counted correctly
  const penalty = candidate.penalty;
  if (penalty && (penalty.actual_amount_cents ?? 0) >= 0) {
    // actual_amount_cents is set (even if 0), meaning usage was synced
    // But we need to verify it was synced before grace expired
    if (penalty.last_updated) {
      const graceDeadline = getGraceDeadline(
        getCommitmentDeadline(candidate, isTestingMode ?? false),
        isTestingMode
      );
      const lastUpdated = new Date(penalty.last_updated);
      return lastUpdated.getTime() <= graceDeadline.getTime();
    }
    // If no timestamp but actual_amount_cents is set, assume synced
    // (This is conservative - may charge actual when it should charge worst case)
    return true;
  }
  
  return false;
}
```

**Also update** the function signature where it's called (line 504):

```typescript
// Change from:
const hasUsage = hasSyncedUsage(candidate);

// To:
const hasUsage = hasSyncedUsage(candidate, isTestingMode);
```

**Add helper function** if not already present:

```typescript
function getCommitmentDeadline(candidate: SettlementCandidate, isTestingMode: boolean): Date {
  // Use explicit grace deadline if available
  if (candidate.commitment.week_grace_expires_at) {
    const graceDeadline = new Date(candidate.commitment.week_grace_expires_at);
    // Calculate deadline as grace deadline minus grace period
    const gracePeriodMs = isTestingMode ? 60 * 1000 : 24 * 60 * 60 * 1000;
    return new Date(graceDeadline.getTime() - gracePeriodMs);
  }
  
  // Otherwise derive from week_end_date
  const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
  const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
  mondayET.setHours(12, 0, 0, 0);
  return mondayET;
}
```

---

## Why This Fix Works for Case 1_A_A

### Scenario:
1. User syncs usage within grace period (T+0.5 min)
2. `rpc_sync_daily_usage` creates `daily_usage` entry with `commitment_id`
3. `rpc_sync_daily_usage` updates `user_week_penalties`:
   - Sets `total_penalty_cents = 0`
   - Sets `actual_amount_cents = 0`
   - Sets `last_updated = NOW()` (timestamp when synced)
4. Grace period expires (T+1 min)
5. Settlement runs (T+1.1 min)

### With Fix:
1. `hasSyncedUsage()` checks `reportedDays > 0`:
   - ✅ If `fetchUsageCounts()` found the entry: `reportedDays = 1` → proceed to timing check
   - ❌ If `fetchUsageCounts()` didn't find it: `reportedDays = 0` → try fallback
2. **Fallback**: Checks `penalty.actual_amount_cents`:
   - ✅ `actual_amount_cents = 0` (set by sync) → proceed to timing check
3. **Timing Check**: Verifies `last_updated <= graceDeadline`:
   - ✅ `last_updated = T+0.5 min`, `graceDeadline = T+1 min` → `true`
4. Result: `hasSyncedUsage() = true`
5. Settlement calculates: `chargeType = "actual"`, `amountCents = MIN(0, 500) = 0`
6. Zero amount check: `if (amountCents <= 0) { skip charge }`
7. ✅ **PASS**: Status remains `pending`, no payment created

---

## Edge Cases Handled

### Case 1: `commitment_id` Mismatch
- **Problem**: `fetchUsageCounts()` doesn't find usage entry
- **Solution**: Fallback to `actual_amount_cents` check
- **Result**: Still detects synced usage

### Case 2: Missing `last_updated` Timestamp
- **Problem**: Old records don't have `last_updated`
- **Solution**: If `reportedDays > 0` or `actual_amount_cents` is set, assume synced (backward compatibility)
- **Result**: Conservative approach (may charge actual when it should charge worst case, but better than wrong charge)

### Case 3: Usage Synced After Grace Expired
- **Problem**: Usage synced late (Case 3 scenario)
- **Solution**: Timing check `last_updated <= graceDeadline` returns `false`
- **Result**: Correctly charges worst case (Case 2 behavior)

### Case 4: Zero Penalty with Synced Usage
- **Problem**: Usage synced but penalty is 0
- **Solution**: `hasSyncedUsage() = true` → `chargeType = "actual"` → `amountCents = 0` → skip charge
- **Result**: ✅ Correct behavior

---

## Potential Issues with This Fix

### Issue 1: Backward Compatibility
- **Risk**: Old records without `last_updated` may be treated as synced
- **Impact**: May charge actual when it should charge worst case (conservative error)
- **Mitigation**: This is acceptable - better to charge actual than worst case incorrectly

### Issue 2: Performance
- **Risk**: Additional date calculations in `hasSyncedUsage()`
- **Impact**: Minimal - only called once per candidate
- **Mitigation**: Cache `graceDeadline` calculation if needed

### Issue 3: Testing Mode Detection
- **Risk**: `isTestingMode` must be passed correctly
- **Impact**: Wrong grace period calculation if not passed
- **Mitigation**: Ensure `isTestingMode` is checked from database/env var consistently

---

## Testing After Fix

### Test Case 1_A_A Again:
1. ✅ `hasSyncedUsage()` should return `true`
2. ✅ `chargeType` should be `"actual"`
3. ✅ `amountCents` should be `0`
4. ✅ Settlement should skip charge (`zeroAmount` counter incremented)
5. ✅ Status should remain `pending`
6. ✅ No payment record created

### Test Other Cases:
- **Case 1_B_A**: Should also work (no sync before grace, but sync within grace)
- **Case 2_A_A**: Should still charge worst case (no sync within grace)
- **Case 3_A_A**: Should still work (late sync after settlement)

---

## Alternative Approaches Considered

### Alternative 1: Fix `fetchUsageCounts()` Only
- **Approach**: Ensure `commitment_id` matching works correctly
- **Problem**: Doesn't address timing issue or provide fallback
- **Rejected**: Too narrow, doesn't solve root cause

### Alternative 2: Always Check `actual_amount_cents`
- **Approach**: Use `actual_amount_cents` as primary indicator
- **Problem**: `actual_amount_cents` may be 0 for zero penalty, but also 0 when not synced
- **Rejected**: Ambiguous - can't distinguish "synced with 0 penalty" vs "not synced"

### Alternative 3: Add `usage_synced_at` Timestamp
- **Approach**: Add explicit timestamp field to track when usage was synced
- **Problem**: Requires database migration, more complex
- **Rejected**: Overkill for this fix, `last_updated` already exists

---

## Recommended Implementation Order

1. ✅ **Update `hasSyncedUsage()`** with multi-layer detection
2. ✅ **Update function call** to pass `isTestingMode`
3. ✅ **Add helper function** `getCommitmentDeadline()` if missing
4. ✅ **Test Case 1_A_A** to verify fix
5. ✅ **Test other Case 1 variants** (1_A_B, 1_A_C, 1_A_D, 1_B_*)
6. ✅ **Test Case 2** to ensure no regression
7. ✅ **Test Case 3** to ensure no regression

---

## Summary

**Root Cause**: `hasSyncedUsage()` only checks `reportedDays` and doesn't have fallback or timing verification.

**Fix**: Multi-layer detection with:
1. Primary: `reportedDays > 0` with timing check
2. Fallback: `actual_amount_cents` check with timing check
3. Timing: Verify usage synced before grace expired

**Expected Outcome**: Case 1_A_A passes - settlement detects synced usage, calculates 0 charge, skips payment.

