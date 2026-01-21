# Case 1_A_A Failure Analysis

**Date**: 2026-01-20  
**Test Case**: Case 1_A_A (Sync Before Grace Begins + 0 Usage + 0 Penalty)  
**Status**: ❌ FAILED

---

## Problem Summary

Settlement charged worst case (`500` cents) instead of skipping charge (0 penalty). The test executed **Case 2 behavior** instead of **Case 1 behavior**.

---

## Root Cause Analysis

### Issue 1: `hasSyncedUsage()` Logic Mismatch

There are **two different implementations** of `hasSyncedUsage()`:

#### Implementation A: `bright-service/index.ts` (Lines 251-274)
```typescript
function hasSyncedUsage(candidate: SettlementCandidate, isTestingMode: boolean): boolean {
  // Checks actual_amount_cents AND last_updated timestamp
  // Only counts usage synced AFTER the deadline
  const penalty = candidate.penalty;
  if (!penalty || (penalty.actual_amount_cents ?? 0) <= 0) {
    return false;
  }
  const deadline = getCommitmentDeadline(candidate, isTestingMode);
  const lastUpdated = new Date(penalty.last_updated);
  return lastUpdated.getTime() > deadline.getTime();
}
```

#### Implementation B: `bright-service/run-weekly-settlement.ts` (Lines 225-227)
```typescript
function hasSyncedUsage(candidate: SettlementCandidate): boolean {
  return candidate.reportedDays > 0;
}
```

**Problem**: `run-weekly-settlement.ts` uses the simpler version that only checks if `reportedDays > 0`, but doesn't verify:
1. **When** the usage was synced (before or after grace period)
2. **If** the usage entry has the correct `commitment_id`

### Issue 2: `fetchUsageCounts()` May Not Find Usage

The `fetchUsageCounts()` function queries `daily_usage` by `commitment_id`:

```typescript
async function fetchUsageCounts(
  supabase: ReturnType<typeof createClient>,
  commitmentIds: string[]
): Promise<Map<string, number>> {
  const { data, error } = await supabase
    .from("daily_usage")
    .select("commitment_id")
    .in("commitment_id", commitmentIds);
  
  // Counts entries per commitment_id
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    if (!row?.commitment_id) continue;
    counts.set(row.commitment_id, (counts.get(row.commitment_id) ?? 0) + 1);
  }
  return counts;
}
```

**Potential Issues**:
1. If `commitment_id` is NULL or doesn't match, usage won't be counted
2. If usage was synced but `commitment_id` wasn't set correctly, `reportedDays` will be 0
3. Timing issue: If usage was synced AFTER settlement ran, it won't be counted

### Issue 3: Zero Penalty Still Gets Charged

Even if usage is detected, when `total_penalty_cents = 0`, the settlement logic should skip charging:

```typescript
if (amountCents <= 0) {
  summary.zeroAmount += 1;
  continue;  // Skip charge
}
```

But in this case, it charged worst case (`500` cents), which means:
- `hasUsage` was `false` (so `chargeType = "worst_case"`)
- `amountCents = max_charge_cents = 500` (not 0)
- So the zero-amount check didn't trigger

---

## Evidence from Test Results

From the verification output:
- ✅ `total_penalty_cents = 0` (usage was synced with 0 penalty)
- ✅ `usage_count = 1` (usage entry exists)
- ❌ `settlement_status = "charged_worst_case"` (should be `pending`)
- ❌ `charged_amount_cents = 500` (should be 0)
- ❌ Payment created with `penalty_worst_case` type

**Conclusion**: Settlement did NOT detect the synced usage, so it charged worst case.

---

## Suggested Fixes

### Fix 1: Use Consistent `hasSyncedUsage()` Logic

**Option A**: Update `run-weekly-settlement.ts` to use the same logic as `index.ts`:

```typescript
function hasSyncedUsage(candidate: SettlementCandidate, isTestingMode?: boolean): boolean {
  // Check if usage was synced within grace period
  // Method 1: Check reportedDays (usage entries exist)
  if (candidate.reportedDays > 0) {
    // Verify usage was synced before grace period expired
    const penalty = candidate.penalty;
    if (penalty && penalty.last_updated) {
      const graceDeadline = getGraceDeadline(
        getCommitmentDeadline(candidate, isTestingMode ?? false),
        isTestingMode
      );
      const lastUpdated = new Date(penalty.last_updated);
      // Usage must be synced before grace expires for Case 1
      return lastUpdated.getTime() <= graceDeadline.getTime();
    }
    // If no last_updated, assume usage was synced (backward compatibility)
    return true;
  }
  return false;
}
```

**Option B**: Use `actual_amount_cents` check (like `index.ts`):

```typescript
function hasSyncedUsage(candidate: SettlementCandidate, isTestingMode?: boolean): boolean {
  const penalty = candidate.penalty;
  if (!penalty) return false;
  
  // If actual_amount_cents is set, usage was synced
  // But we need to check if it was synced within grace period
  if ((penalty.actual_amount_cents ?? 0) > 0 || candidate.reportedDays > 0) {
    // Check timing: usage must be synced before grace expires
    if (penalty.last_updated) {
      const graceDeadline = getGraceDeadline(
        getCommitmentDeadline(candidate, isTestingMode ?? false),
        isTestingMode
      );
      const lastUpdated = new Date(penalty.last_updated);
      return lastUpdated.getTime() <= graceDeadline.getTime();
    }
    // If no timestamp, check if reportedDays > 0 (usage exists)
    return candidate.reportedDays > 0;
  }
  return false;
}
```

### Fix 2: Verify `commitment_id` in Usage Entries

Add logging/debugging to verify `commitment_id` is set correctly:

```typescript
async function fetchUsageCounts(
  supabase: ReturnType<typeof createClient>,
  commitmentIds: string[]
): Promise<Map<string, number>> {
  if (commitmentIds.length === 0) return new Map();
  
  const { data, error } = await supabase
    .from("daily_usage")
    .select("commitment_id, user_id, date")
    .in("commitment_id", commitmentIds);

  if (error) {
    console.error(`Failed to fetch daily_usage rows: ${error.message}`);
    throw new Error(`Failed to fetch daily_usage rows: ${error.message}`);
  }

  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    if (!row?.commitment_id) {
      console.warn(`Usage entry missing commitment_id:`, row);
      continue;
    }
    counts.set(row.commitment_id, (counts.get(row.commitment_id) ?? 0) + 1);
  }
  
  // Debug logging
  console.log(`fetchUsageCounts: Found ${data?.length || 0} usage entries for ${commitmentIds.length} commitments`);
  console.log(`fetchUsageCounts: Counts:`, Object.fromEntries(counts));
  
  return counts;
}
```

### Fix 3: Handle Zero Penalty in Worst Case

Even when charging worst case, if `total_penalty_cents = 0` and usage was synced, we should skip charge:

```typescript
const chargeType: ChargeType = hasUsage ? "actual" : "worst_case";
const amountCents = getChargeAmount(candidate, chargeType);

// Special case: If usage was synced but penalty is 0, skip charge
if (hasUsage && getActualPenaltyCents(candidate) === 0) {
  summary.zeroAmount += 1;
  continue;  // Skip charge - zero penalty
}

if (amountCents <= 0) {
  summary.zeroAmount += 1;
  continue;
}
```

**However**, this might not be the right fix because:
- If usage wasn't synced within grace period, we should charge worst case
- But if usage WAS synced (even with 0 penalty), we should skip charge

The real issue is that `hasUsage` is returning `false` when it should return `true`.

---

## Recommended Fix

**Primary Fix**: Update `hasSyncedUsage()` in `run-weekly-settlement.ts` to:
1. Check `reportedDays > 0` (usage entries exist)
2. Verify usage was synced **before grace period expired** (check `last_updated` timestamp)
3. Fall back to `reportedDays > 0` if timestamp is not available

**Secondary Fix**: Add better logging to debug why usage isn't being detected.

---

## Testing After Fix

After implementing the fix, re-run Case 1_A_A and verify:
1. ✅ `settlement_status = "pending"` (or remains unchanged)
2. ✅ `charged_amount_cents = 0` (or null)
3. ✅ No payment record created
4. ✅ `zeroAmount` counter incremented in settlement summary

---

## Questions to Investigate

1. **When was the usage entry created?** (Check `reported_at` timestamp in `daily_usage`)
2. **Does the usage entry have the correct `commitment_id`?** (Should match commitment `b5d0f923-4c90-44b3-9685-39d04ee1635e`)
3. **What was the `reportedDays` value when settlement ran?** (Check settlement logs)
4. **Was `last_updated` set on the penalty record?** (Check `user_week_penalties.last_updated`)

---

## Next Steps

1. ✅ Analyze root cause (this document)
2. ⏳ Implement fix for `hasSyncedUsage()` logic
3. ⏳ Add debugging/logging to `fetchUsageCounts()`
4. ⏳ Re-test Case 1_A_A
5. ⏳ Verify all 24 test cases still work correctly

