# Grace Period Logic Analysis

**Date**: 2025-01-01  
**Purpose**: Analyze if code matches documented logic for grace period timing

---

## Documented Logic

- **Monday 12:00 ET**: Week deadline (week_end_date)
- **Tuesday 12:00 ET**: Grace period expires, settlement runs
- **CASE 1**: User syncs **after Monday 12:00 ET but before Tuesday 12:00 ET** → Charge actual
- **CASE 2**: User does **NOT sync** during grace period → Charge worst case on Tuesday 12:00 ET
- **CASE 3**: User syncs **after Tuesday 12:00 ET** → Late sync, reconciliation

---

## Code Analysis

### 1. Settlement Decision Logic

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`  
**Lines**: 430-442

```typescript
for (const candidate of candidates) {
  const hasUsage = hasSyncedUsage(candidate);
  
  if (shouldSkipBecauseSettled(candidate)) {
    summary.alreadySettled += 1;
    continue;
  }
  
  if (!hasUsage && !isGracePeriodExpired(candidate)) {
    summary.graceNotExpired += 1;
    continue;  // Skip - wait for grace period to expire
  }
  
  const chargeType: ChargeType = hasUsage ? "actual" : "worst_case";
  const amountCents = getChargeAmount(candidate, chargeType);
  // ... charge user
}
```

**Analysis**:
- ✅ If user **HAS synced usage** → Charges actual (doesn't check grace period)
- ✅ If user **HASN'T synced** → Only charges if grace period expired
- ✅ Logic matches documented behavior

**Issue**: The grace period check itself has a bug (see below).

---

### 2. Grace Period Expiration Check

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`  
**Lines**: 205-212

```typescript
function isGracePeriodExpired(candidate: SettlementCandidate, reference: Date = new Date()): boolean {
  const explicit = candidate.commitment.week_grace_expires_at;
  if (explicit) return new Date(explicit).getTime() <= reference.getTime();

  // Derived calculation
  const derived = new Date(`${candidate.commitment.week_end_date}T00:00:00Z`);
  derived.setUTCDate(derived.getUTCDate() + 1);
  return derived.getTime() <= reference.getTime();
}
```

**Analysis**:
- ❌ **BUG**: Uses `T00:00:00Z` (midnight UTC) instead of Tuesday 12:00 ET
- ❌ **BUG**: `week_end_date` is a date string (e.g., "2025-01-13"), adding `T00:00:00Z` makes it Monday midnight UTC
- ❌ **BUG**: Adding 1 day makes it Tuesday midnight UTC, which is:
  - **EST**: Monday 7:00 PM ET (5 hours before Tuesday 12:00 ET)
  - **EDT**: Monday 8:00 PM ET (4 hours before Tuesday 12:00 ET)
- ❌ **BUG**: Grace period would expire **too early** (Monday evening instead of Tuesday noon)

**Expected Behavior**:
- Should be: Tuesday 12:00 ET (Tuesday 17:00 UTC in EST, or Tuesday 16:00 UTC in EDT)
- Currently: Tuesday 00:00 UTC (Monday evening in ET)

---

### 3. Week Target Resolution

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`  
**Lines**: 61-82

```typescript
function resolveWeekTarget(options?: { override?: string; now?: Date }): WeekTarget {
  // ...
  const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE); // America/New_York
  const monday = new Date(reference);
  const dayOfWeek = reference.getDay();
  const daysSinceMonday = (dayOfWeek + 6) % 7;
  monday.setDate(monday.getDate() - daysSinceMonday);
  monday.setHours(12, 0, 0, 0);  // Monday 12:00 ET
  
  const weekEndDate = formatDate(monday);
  const graceDeadline = new Date(monday);
  graceDeadline.setDate(graceDeadline.getDate() + 1);  // Tuesday 12:00 ET (preserves time)
  
  return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
}
```

**Analysis**:
- ✅ Correctly calculates Monday 12:00 ET
- ✅ Correctly calculates Tuesday 12:00 ET (by adding 1 day and preserving 12:00 time)
- ✅ This function is used for determining which week to settle, but **NOT used in `isGracePeriodExpired`**

**Issue**: `resolveWeekTarget` calculates grace deadline correctly, but `isGracePeriodExpired` doesn't use it.

---

### 4. Commitment Creation

**File**: `supabase/remote_rpcs/rpc_create_commitment.sql`

**Analysis**:
- ❌ **MISSING**: `week_grace_expires_at` is **NOT set** when creating commitments
- ❌ This means `isGracePeriodExpired` always uses the **derived calculation** (which is wrong)
- ❌ The explicit field is never populated, so the fallback bug always applies

---

## Summary of Issues

### Issue 1: Grace Period Expiration Time is Wrong
- **Location**: `isGracePeriodExpired()` function
- **Problem**: Uses Tuesday 00:00 UTC instead of Tuesday 12:00 ET
- **Impact**: Grace period expires ~16-17 hours too early (Monday evening instead of Tuesday noon)
- **Severity**: **HIGH** - Users could be charged worst case too early

### Issue 2: week_grace_expires_at Never Set
- **Location**: `rpc_create_commitment.sql`
- **Problem**: Field exists but is never populated
- **Impact**: Always uses buggy derived calculation
- **Severity**: **MEDIUM** - Makes Issue 1 always apply

### Issue 3: Logic Flow is Correct (But Timing is Wrong)
- **Location**: Settlement decision logic
- **Status**: ✅ Logic flow matches documentation
- **Problem**: Timing check is wrong, so correct logic runs at wrong time

---

## What the Code Actually Does

### Current Behavior (Due to Bug)

1. **Monday 12:00 ET**: Week deadline
2. **Monday Evening (~7-8 PM ET)**: Grace period expires (due to bug - should be Tuesday 12:00 ET)
3. **If user synced before Monday evening**: Charge actual ✅
4. **If user didn't sync by Monday evening**: Charge worst case ❌ (too early!)
5. **Tuesday 12:00 ET**: Settlement runs (but grace already expired, so worst case already charged)

**Problem**: Users who sync on Monday night or Tuesday morning (before Tuesday noon) would still get charged worst case because grace period already expired on Monday evening.

---

## What Should Happen (Per Documentation)

1. **Monday 12:00 ET**: Week deadline
2. **Tuesday 12:00 ET**: Grace period expires, settlement runs
3. **If user synced before Tuesday 12:00 ET**: Charge actual ✅
4. **If user didn't sync by Tuesday 12:00 ET**: Charge worst case ✅
5. **If user syncs after Tuesday 12:00 ET**: Late sync, reconciliation ✅

---

## Code vs Documentation Mismatch

| Aspect | Documentation | Code (Current) | Match? |
|--------|--------------|----------------|--------|
| Grace period expires | Tuesday 12:00 ET | Monday evening (~7-8 PM ET) | ❌ NO |
| User syncs Monday night | Should charge actual | Charges worst case (grace expired) | ❌ NO |
| User syncs Tuesday morning | Should charge actual | Charges worst case (grace expired) | ❌ NO |
| Settlement runs | Tuesday 12:00 ET | Tuesday 12:00 ET | ✅ YES |
| Logic flow | Correct | Correct | ✅ YES |
| Timing check | Correct | Wrong | ❌ NO |

---

## Recommended Fix

### Fix 1: Correct Grace Period Calculation

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

**Current (WRONG)**:
```typescript
const derived = new Date(`${candidate.commitment.week_end_date}T00:00:00Z`);
derived.setUTCDate(derived.getUTCDate() + 1);
```

**Should be**:
```typescript
// week_end_date is Monday (e.g., "2025-01-13")
// Need Tuesday 12:00 ET
const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
// Convert to ET timezone
const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
const tuesdayET = new Date(mondayET);
tuesdayET.setDate(tuesdayET.getDate() + 1);  // Tuesday 12:00 ET
tuesdayET.setHours(12, 0, 0, 0);
return tuesdayET.getTime() <= reference.getTime();
```

**OR** use the existing `resolveWeekTarget` logic:
```typescript
const weekTarget = resolveWeekTarget({ override: candidate.commitment.week_end_date });
const graceDeadline = new Date(weekTarget.graceDeadlineIso);
return graceDeadline.getTime() <= reference.getTime();
```

### Fix 2: Set week_grace_expires_at on Commitment Creation

**File**: `supabase/remote_rpcs/rpc_create_commitment.sql`

Add to INSERT statement:
```sql
week_grace_expires_at := (p_deadline_date::timestamp AT TIME ZONE 'America/New_York') + INTERVAL '1 day 12 hours';
```

This sets it to Tuesday 12:00 ET explicitly.

---

## Impact Assessment

### Current Bug Impact
- **Users who sync Monday evening/Tuesday morning**: Charged worst case (should be actual)
- **Timing**: Grace expires ~16-17 hours too early
- **User Experience**: Users think they have until Tuesday noon, but grace expires Monday evening

### After Fix
- **Users who sync before Tuesday 12:00 ET**: Charged actual ✅
- **Users who don't sync by Tuesday 12:00 ET**: Charged worst case ✅
- **Matches documentation**: ✅

---

## Conclusion

**The code logic flow is correct**, but **the grace period expiration time calculation is wrong**. The code currently expires the grace period on Monday evening (due to using midnight UTC), when it should expire on Tuesday 12:00 ET.

This means:
- ✅ The decision logic (charge actual vs worst case) is correct
- ❌ The timing check (when grace expires) is wrong
- ❌ Users syncing Monday night/Tuesday morning get charged worst case incorrectly

**Recommendation**: Fix the `isGracePeriodExpired()` function to use Tuesday 12:00 ET instead of Tuesday 00:00 UTC.

---

**End of Analysis**


