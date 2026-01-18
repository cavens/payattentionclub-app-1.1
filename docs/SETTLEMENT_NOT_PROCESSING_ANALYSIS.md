# Settlement Not Processing Analysis
**Date**: 2026-01-17  
**Commitment ID**: `42910fec-d202-4275-a0c1-8a74c01f4356`  
**Issue**: Payment not processed, settlement not done

---

## ✅ Confirmed: $5.00 Minimum is Correct

**Status**: ✅ **CORRECT**
- Current value: `500` cents ($5.00) ✅
- Source file: `calculate_max_charge_cents.sql` has `500` ✅
- Migration file with $15.00 is outdated/incorrect
- **No action needed** - $5.00 minimum is correct

---

## Timeline Analysis

### Commitment Details:
- **Created**: `2026-01-17T16:44:56.922874+00:00`
- **Deadline** (`week_end_timestamp`): `2026-01-17T16:47:56.886+00:00` ✅
- **Grace Period Should Expire**: `2026-01-17T16:48:56.886+00:00` (1 minute after deadline)
- **Verification Time**: `2026-01-17T16:50:29.453282+00:00`

### Status at Verification:
- ✅ Deadline passed: **2m 33s ago**
- ✅ Grace period expired: **1m 33s ago**
- ❌ Settlement status: `pending` (should be `settled`)
- ❌ Payment: None created

---

## Root Cause Analysis

### Issue: Testing Mode Mismatch in Grace Period Calculation

**Problem**:
The settlement function has a **mismatch** between how it determines testing mode and how the grace period is calculated:

1. **Settlement Function** (`bright-service/index.ts`):
   - Checks `app_config` table for `testing_mode = 'true'` ✅
   - Sets `isTestingMode` variable dynamically ✅
   - Uses this to determine which week to process ✅

2. **Grace Period Calculation** (`isGracePeriodExpired()`):
   - Calls `getGraceDeadline(deadline)` from `_shared/timing.ts`
   - `getGraceDeadline()` uses `TESTING_MODE` **constant** (line 123)
   - `TESTING_MODE` is evaluated at **module load time** from environment variable
   - If `TESTING_MODE` env var is not set, it defaults to `false`
   - This causes `getGraceDeadline()` to use **normal mode** (24 hours) instead of testing mode (1 minute)

**Code Flow**:
```typescript
// In bright-service/index.ts
isGracePeriodExpired(candidate) {
  const deadline = getCommitmentDeadline(candidate); // Uses week_end_timestamp ✅
  const graceDeadline = getGraceDeadline(deadline); // ❌ Uses TESTING_MODE constant
  return graceDeadline.getTime() <= reference.getTime();
}

// In _shared/timing.ts
export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) { // ❌ This is a constant, not dynamic
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS); // 1 minute
  }
  // Normal mode: 24 hours
  return new Date(weekEndDate.getTime() + (24 * 60 * 60 * 1000));
}
```

**Result**:
- If `TESTING_MODE` env var is `false` or not set:
  - `getGraceDeadline()` calculates: deadline + 24 hours
  - For deadline `16:47:56`, grace expires at `16:47:56 + 24h = next day 16:47:56`
  - Current time `16:50:29` is **before** next day 16:47:56
  - `isGracePeriodExpired()` returns `false` ❌
  - Settlement skips with `graceNotExpired += 1`

---

## Evidence from Previous Settlement Test

When we triggered settlement earlier, the response showed:
```json
{
  "weekEndDate": "2026-01-17",
  "totalCommitments": 1,
  "graceNotExpired": 1,  // ❌ This confirms grace period check failed
  "alreadySettled": 0,
  "chargedActual": 0,
  "chargedWorstCase": 0
}
```

This confirms that the settlement function thought the grace period hadn't expired yet, even though it had.

---

## Solution

### Option 1: Pass `isTestingMode` to `getGraceDeadline()` (Recommended)

**Change**: Make `getGraceDeadline()` accept an `isTestingMode` parameter instead of using the constant.

**Files to Update**:
1. `supabase/functions/_shared/timing.ts`:
   ```typescript
   export function getGraceDeadline(weekEndDate: Date, isTestingMode?: boolean): Date {
     const useTestingMode = isTestingMode ?? TESTING_MODE; // Fallback to constant
     if (useTestingMode) {
       return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
     }
     // Normal mode...
   }
   ```

2. `supabase/functions/bright-service/index.ts`:
   ```typescript
   function isGracePeriodExpired(candidate: SettlementCandidate, reference: Date = new Date()): boolean {
     // ... existing code ...
     const deadline = getCommitmentDeadline(candidate);
     const graceDeadline = getGraceDeadline(deadline, isTestingMode); // Pass isTestingMode
     // ...
   }
   ```

### Option 2: Set `TESTING_MODE` Environment Variable

**Change**: Set `TESTING_MODE=true` in Supabase Edge Function secrets.

**Pros**:
- Simple fix
- No code changes needed

**Cons**:
- Still relies on environment variable (less flexible)
- Doesn't use `app_config` table as source of truth

---

## Additional Issues Found

### Issue 2: `week_grace_expires_at` is NULL

**Status**: Low Priority
- Field exists but is never set in `rpc_create_commitment`
- Settlement function calculates it dynamically (works, but less efficient)
- **Not blocking** - functionality works with fallback logic

### Issue 3: Usage Details Not Shown

**Status**: Informational
- Verification shows `usage_count: 1` but no actual usage data
- Likely a limitation of the verification endpoint
- **Not blocking** - can check usage separately

---

## Summary

| Issue | Severity | Root Cause | Solution |
|-------|----------|------------|----------|
| Settlement not processing | **HIGH** | `getGraceDeadline()` uses `TESTING_MODE` constant instead of dynamic `isTestingMode` | Pass `isTestingMode` parameter to `getGraceDeadline()` |
| `week_grace_expires_at` is NULL | Low | Field not set in `rpc_create_commitment` | Optional: Set field explicitly |
| Usage details not shown | Info | Verification endpoint limitation | Optional: Enhance endpoint |

---

## Recommended Action

**URGENT**: Fix the testing mode mismatch in grace period calculation.

**Steps**:
1. Update `getGraceDeadline()` to accept `isTestingMode` parameter
2. Update `isGracePeriodExpired()` to pass `isTestingMode` to `getGraceDeadline()`
3. Test settlement again - should now process correctly

This will ensure that when testing mode is enabled via `app_config` table, the grace period calculation uses 1 minute instead of 24 hours.


