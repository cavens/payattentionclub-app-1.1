# Case 3 Fix Suggestions

## Problem Summary

Three Case 3 test cases are failing due to logic issues in settlement and reconciliation:

1. **Case 3_A_A**: Sync before grace (0 usage) + late sync (0 usage)
   - Expected: Charge worst case (4200), then reconcile to refund
   - Actual: No charge (settlement skipped because it saw 0 usage from before-grace sync)

2. **Case 3_A_D**: Sync before grace (50 min, 0 penalty) + late sync (50 min, 0 penalty)
   - Expected: Charge worst case (4200), then reconcile to refund
   - Actual: No charge (settlement skipped because it saw 0 penalty from before-grace sync)

3. **Case 3_B_D**: No sync before grace + late sync (50 min, 0 penalty)
   - Expected: Charge worst case (4200), then reconcile to refund (2 payments total)
   - Actual: Charge worst case, reconcile to refund, but only 1 payment (no refund payment record)

---

## Root Cause Analysis

### Issue 1: `hasSyncedUsage()` Logic (Cases 3_A_A and 3_A_D)

**Current Logic:**
```typescript
// Checks if last_updated <= graceDeadline
hasUsage = lastUpdated.getTime() <= graceDeadline.getTime();
```

**Problem:**
- For Case 3, usage is synced **BEFORE grace begins** (before Monday deadline)
- The check `last_updated <= graceDeadline` returns `true` because:
  - `last_updated` = Monday 11:59 (before deadline)
  - `graceDeadline` = Tuesday 12:00 (when grace expires)
  - Monday 11:59 < Tuesday 12:00 = TRUE
- This makes `hasUsage = true`, so settlement tries to charge "actual" penalty
- Since actual penalty is 0, settlement skips the charge
- Result: No worst-case charge, nothing to reconcile

**What Should Happen:**
- `hasSyncedUsage()` should only return `true` if usage was synced **WITHIN grace** (after deadline, before grace expires)
- Usage synced **BEFORE grace** should be treated as "not synced within grace"
- Settlement should charge worst case, then reconciliation handles the refund

### Issue 2: Full Refund Payment Record (Case 3_B_D)

**Current Logic:**
```typescript
// Only create refund payment record if it's a partial refund
if (!isFullRefund) {
  await supabase.from("payments").insert({...});
}
```

**Problem:**
- For full refunds, the code updates status to "refunded" but doesn't create a separate payment record
- Test expects 2 payments: initial charge + refund
- Actual: 1 payment (only initial charge)

**Design Question:**
- Should full refunds create a separate payment record for audit/tracking purposes?
- Or is updating the status sufficient?

---

## Suggested Fixes

### Fix 1: Update `hasSyncedUsage()` to Check "Within Grace" Not "Before Grace Expires"

**Location:** 
- `supabase/functions/bright-service/run-weekly-settlement.ts` (line 225)
- `supabase/tests/test_settlement_matrix_24_cases.ts` (line 916)

**Change:**
Instead of checking `last_updated <= graceDeadline`, check if usage was synced **after the deadline** but **before grace expires**:

```typescript
function hasSyncedUsage(candidate: SettlementCandidate, isTestingMode?: boolean): boolean {
  // Method 1: Check if usage entries exist (primary indicator)
  if (candidate.reportedDays > 0) {
    const penalty = candidate.penalty;
    if (penalty?.last_updated) {
      const graceDeadline = getCommitmentGraceDeadline(candidate, isTestingMode);
      const weekDeadline = getCommitmentWeekDeadline(candidate); // NEW: Get week deadline
      const lastUpdated = new Date(penalty.last_updated);
      
      // Usage must be synced WITHIN grace (after deadline, before grace expires)
      return lastUpdated.getTime() > weekDeadline.getTime() && 
             lastUpdated.getTime() <= graceDeadline.getTime();
    }
    return false; // No timestamp = not synced within grace
  }
  
  // Method 2: Fallback - check actual_amount_cents
  const penalty = candidate.penalty;
  if (penalty && (penalty.actual_amount_cents ?? 0) >= 0) {
    if (penalty.last_updated) {
      const graceDeadline = getCommitmentGraceDeadline(candidate, isTestingMode);
      const weekDeadline = getCommitmentWeekDeadline(candidate); // NEW
      const lastUpdated = new Date(penalty.last_updated);
      
      // Usage must be synced WITHIN grace
      return lastUpdated.getTime() > weekDeadline.getTime() && 
             lastUpdated.getTime() <= graceDeadline.getTime();
    }
    return false; // No timestamp = not synced within grace
  }
  
  return false;
}

// NEW: Helper function to get week deadline
function getCommitmentWeekDeadline(candidate: SettlementCandidate): Date {
  // week_end_date is the Monday deadline
  const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
  const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
  mondayET.setHours(12, 0, 0, 0);
  return mondayET;
}
```

**Impact:**
- Cases 3_A_A and 3_A_D: Usage synced before grace will correctly return `hasUsage = false`, triggering worst-case charge
- Case 1: Usage synced within grace will still return `hasUsage = true` (correct)
- Case 2: No usage synced will return `hasUsage = false` (correct)

---

### Fix 2: Create Refund Payment Record for Full Refunds (Optional)

**Location:** 
- `supabase/tests/test_settlement_matrix_24_cases.ts` (line 1083)
- `supabase/functions/quick-handler/settlement-reconcile.ts` (if it exists)

**Option A: Always Create Refund Payment Record**
```typescript
if (delta < 0) {
  const refundAmount = Math.abs(delta);
  
  if (refundAmount > 0) {
    const isFullRefund = refundAmount === chargedAmount;
    
    // Update penalty record
    await supabase.from("user_week_penalties").update({...});
    
    // ALWAYS create refund payment record (for audit trail)
    await supabase.from("payments").insert({
      user_id: userId,
      week_start_date: weekEndDate,
      amount_cents: refundAmount,
      currency: "usd",
      stripe_payment_intent_id: `pi_refund_${Date.now()}`,
      status: "succeeded",
      payment_type: "penalty_refund",
    });
  }
}
```

**Option B: Update Test Expectations**
If full refunds shouldn't create separate payment records (current design), update test expectations:

```typescript
// Case 3_B_D expected:
expected: {
  settlementStatus: ["refunded", "refunded_partial"],
  chargedAmountCents: 0,
  actualAmountCents: 0,
  paymentCount: 1, // Changed from 2 to 1
  // ... rest
}
```

**Recommendation:** 
- Option A is better for audit/tracking purposes
- Creates a complete payment history
- Matches Stripe's behavior (refunds are separate payment intents)

---

## Implementation Priority

1. **Fix 1 (hasSyncedUsage)**: HIGH PRIORITY
   - Fixes Cases 3_A_A and 3_A_D
   - Critical for correct settlement behavior
   - Must be applied to both production code and test simulation

2. **Fix 2 (Refund Payment Record)**: MEDIUM PRIORITY
   - Fixes Case 3_B_D
   - Design decision: should full refunds create payment records?
   - If yes, implement Option A
   - If no, update test expectations (Option B)

---

## Testing After Fixes

After implementing Fix 1:
- Case 3_A_A: Should charge 4200, then reconcile to refund
- Case 3_A_D: Should charge 4200, then reconcile to refund
- Case 1: Should still work (usage synced within grace)
- Case 2: Should still work (no usage synced)

After implementing Fix 2:
- Case 3_B_D: Should have 2 payments (initial charge + refund)
- All other Case 3 scenarios: Should have correct payment counts

