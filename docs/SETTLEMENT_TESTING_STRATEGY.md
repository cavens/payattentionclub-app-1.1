# Settlement Process Testing Strategy

**Status**: 📋 Analysis & Planning  
**Priority**: High  
**Date**: 2025-01-01

## Executive Summary

This document outlines a comprehensive testing strategy for the weekly settlement process, which is one of the most critical and complex flows in the PayAttentionClub application. The settlement process involves multiple components, time-sensitive logic, and edge cases that must be thoroughly validated.

---

## Settlement Flow Overview

### Timeline
- **Monday 12:00 ET**: Week deadline (week_end_date)
- **Monday 12:05 ET**: Reminder email sent (future feature)
- **Tuesday 12:00 ET**: Grace period expires, settlement runs
- **After Tuesday 12:00 ET**: Late syncs trigger reconciliation

### Key Components
1. **UsageSyncManager** (iOS): Syncs daily usage from App Group to backend
2. **rpc_sync_daily_usage** (PostgreSQL): Processes synced usage, calculates penalties, flags reconciliation
3. **bright-service/run-weekly-settlement** (Edge Function): Charges users based on sync status
4. **quick-handler/settlement-reconcile** (Edge Function): Processes refunds/extra charges for late syncs

### Decision Logic
```
IF user has synced usage (daily_usage rows exist):
  → Charge actual penalty (capped at max_charge_cents)
ELSE IF grace period expired (Tuesday 12:00 ET):
  → Charge max_charge_cents (worst case)
ELSE:
  → Skip (wait for grace period to expire)

IF user syncs AFTER being charged:
  → Calculate reconciliation delta
  → IF delta < 0: Refund difference
  → IF delta > 0: Charge additional amount
```

---

## Test Scenarios

### Scenario A: User Syncs Before Tuesday Noon (Happy Path)

**Setup:**
1. Create commitment with:
   - `limit_minutes`: 60
   - `penalty_per_minute_cents`: 10
   - `max_charge_cents`: 4200 (60 × 10 × 7)
   - `week_end_date`: Monday (deadline)
   - `saved_payment_method_id`: Valid Stripe payment method
2. User exceeds limit during week:
   - Day 1: 80 minutes used (20 over = 200 cents)
   - Day 2: 75 minutes used (15 over = 150 cents)
   - Day 3: 70 minutes used (10 over = 100 cents)
   - Total actual penalty: 450 cents

**Test Steps:**
1. **Monday 12:01 ET**: Simulate user opening app
   - Trigger `UsageSyncManager.syncToBackend()`
   - Verify `rpc_sync_daily_usage` is called
   - Verify `daily_usage` rows are created
   - Verify `user_week_penalties.total_penalty_cents = 450`
   - Verify `user_week_penalties.settlement_status = 'pending'`

2. **Tuesday 12:00 ET**: Run settlement
   - Call `bright-service/run-weekly-settlement` with `targetWeek` = Monday date
   - Verify settlement detects synced usage (`hasSyncedUsage = true`)
   - Verify charge type is `"actual"` (not `"worst_case"`)
   - Verify charge amount is 450 cents (actual, not 4200)
   - Verify `user_week_penalties.settlement_status = 'charged_actual'`
   - Verify `user_week_penalties.charged_amount_cents = 450`
   - Verify `user_week_penalties.actual_amount_cents = 450`
   - Verify `payments` record created with `payment_type = 'penalty_actual'`
   - Verify Stripe PaymentIntent created (if using real Stripe)

**Expected Outcome:**
- User charged 450 cents (actual penalty)
- No reconciliation needed
- Settlement status: `charged_actual`

---

### Scenario B: User Does NOT Sync Before Tuesday Noon (Worst Case)

**Setup:**
1. Create commitment (same as Scenario A)
2. User exceeds limit during week (same usage as Scenario A)
3. **User does NOT open app** (no sync)

**Test Steps:**
1. **Monday 12:01 ET**: Verify no sync occurred
   - Check `daily_usage` table: should be empty
   - Check `user_week_penalties`: should not exist or have `total_penalty_cents = 0`

2. **Tuesday 12:00 ET**: Run settlement
   - Call `bright-service/run-weekly-settlement` with `targetWeek` = Monday date
   - Verify settlement detects NO synced usage (`hasSyncedUsage = false`)
   - Verify grace period is expired (`isGracePeriodExpired = true`)
   - Verify charge type is `"worst_case"` (not `"actual"`)
   - Verify charge amount is 4200 cents (max_charge_cents, not actual)
   - Verify `user_week_penalties.settlement_status = 'charged_worst_case'`
   - Verify `user_week_penalties.charged_amount_cents = 4200`
   - Verify `user_week_penalties.actual_amount_cents = 0` (unknown at charge time)
   - Verify `payments` record created with `payment_type = 'penalty_worst_case'`
   - Verify Stripe PaymentIntent created

**Expected Outcome:**
- User charged 4200 cents (worst case)
- Reconciliation will be needed if user syncs later
- Settlement status: `charged_worst_case`

---

### Scenario C: User Syncs AFTER Tuesday Noon (Late Sync - Refund)

**Setup:**
1. Complete Scenario B (user charged worst case: 4200 cents)
2. User's actual penalty was only 450 cents (same as Scenario A)

**Test Steps:**
1. **Wednesday 10:00 ET**: Simulate user opening app (late sync)
   - Trigger `UsageSyncManager.syncToBackend()`
   - Verify `rpc_sync_daily_usage` is called
   - Verify `daily_usage` rows are created
   - Verify `user_week_penalties.total_penalty_cents = 450` (actual)
   - Verify `user_week_penalties.actual_amount_cents = 450`
   - **CRITICAL**: Verify `rpc_sync_daily_usage` detects reconciliation:
     - `needs_reconciliation = true`
     - `reconciliation_delta_cents = -3750` (450 - 4200 = refund owed)
     - `reconciliation_reason = 'late_sync_delta'`
     - `reconciliation_detected_at` is set
     - `settlement_status` remains `'charged_worst_case'` (not changed yet)

2. **Run reconciliation**: Call `quick-handler/settlement-reconcile`
   - Verify it finds the reconciliation candidate
   - Verify delta is negative (refund path)
   - Verify Stripe refund is created for 3750 cents
   - Verify `user_week_penalties.settlement_status = 'refunded'` or `'refunded_partial'`
   - Verify `user_week_penalties.refund_amount_cents = 3750`
   - Verify `user_week_penalties.needs_reconciliation = false` (cleared)
   - Verify `payments` record created with `payment_type = 'penalty_refund'`

**Expected Outcome:**
- User initially charged 4200 cents (worst case)
- User refunded 3750 cents (difference)
- Final charge: 450 cents (actual penalty)
- Settlement status: `refunded` or `refunded_partial`

---

### Scenario D: User Syncs AFTER Tuesday Noon (Late Sync - No Change)

**Setup:**
1. Complete Scenario B (user charged worst case: 4200 cents)
2. User's actual penalty was HIGHER than worst case (edge case - should be capped)

**Test Steps:**
1. **Wednesday 10:00 ET**: Simulate user opening app (late sync)
   - User's actual penalty: 5000 cents (exceeds authorization of 4200)
   - Trigger `UsageSyncManager.syncToBackend()`
   - Verify `rpc_sync_daily_usage` calculates actual: 5000 cents
   - **CRITICAL**: Verify `rpc_sync_daily_usage` caps actual at authorization:
     - `actual_amount_cents = 5000` (true penalty, uncapped)
     - But reconciliation uses **capped actual**: `MIN(5000, 4200) = 4200`
   - Verify reconciliation delta: `4200 - 4200 = 0` (no refund, no extra charge)
   - Verify `needs_reconciliation = false` (delta is 0)
   - **CRITICAL**: Verify validation prevents delta > 0 for late syncs

**Expected Outcome:**
- User charged 4200 cents (worst case)
- Actual penalty was 5000 cents, but capped at 4200
- No reconciliation needed (already charged the cap)
- Settlement status: `charged_worst_case` (unchanged)

**Note**: This scenario tests that the authorization cap is enforced correctly in reconciliation and that extra charges are impossible for late syncs.

---

### Scenario E: Actual Penalty Exceeds Authorization (Capped Charge)

**Setup:**
1. Create commitment with:
   - `limit_minutes`: 1260 (21 hours)
   - `penalty_per_minute_cents`: 10
   - `max_charge_cents`: ~7500 (calculated by `calculate_max_charge_cents`)
2. User syncs before Tuesday noon
3. User's actual penalty: 10000 cents (exceeds authorization)

**Test Steps:**
1. **Monday 12:01 ET**: User syncs
   - Verify `user_week_penalties.total_penalty_cents = 10000`
   - Verify `user_week_penalties.actual_amount_cents = 10000`

2. **Tuesday 12:00 ET**: Run settlement
   - Verify `getChargeAmount(candidate, "actual")` returns 7500 (capped)
   - Verify `user_week_penalties.charged_amount_cents = 7500` (not 10000)
   - Verify `user_week_penalties.actual_amount_cents = 10000` (true penalty, uncapped)
   - Verify `user_week_penalties.settlement_status = 'charged_actual'`
   - Verify Stripe charge is 7500 cents (not 10000)

**Expected Outcome:**
- User charged 7500 cents (capped at authorization)
- Actual penalty was 10000 cents, but charge is capped
- Settlement status: `charged_actual`

---

### Scenario F: Zero Penalty (User Stayed Within Limit)

**Setup:**
1. Create commitment (same as Scenario A)
2. User stays within limit:
   - Day 1: 50 minutes used (under 60 limit)
   - Day 2: 55 minutes used
   - Day 3: 45 minutes used
   - Total actual penalty: 0 cents

**Test Steps:**
1. **Monday 12:01 ET**: User syncs
   - Verify `user_week_penalties.total_penalty_cents = 0`

2. **Tuesday 12:00 ET**: Run settlement
   - Verify settlement detects `amountCents = 0`
   - Verify settlement skips charge (zero amount)
   - Verify `user_week_penalties.settlement_status` remains `'pending'` or set to `'no_charge'`
   - Verify NO `payments` record created
   - Verify NO Stripe PaymentIntent created

**Expected Outcome:**
- No charge (zero penalty)
- No payment record
- Settlement status: `pending` or `no_charge`

---

### Scenario G: Multiple Days of Usage

**Setup:**
1. Create commitment (same as Scenario A)
2. User exceeds limit on multiple days:
   - Day 1: 80 minutes (200 cents)
   - Day 2: 75 minutes (150 cents)
   - Day 3: 70 minutes (100 cents)
   - Day 4: 85 minutes (250 cents)
   - Day 5: 90 minutes (300 cents)
   - Total: 1000 cents

**Test Steps:**
1. **Monday 12:01 ET**: User syncs all days
   - Verify all 5 `daily_usage` rows are created
   - Verify `user_week_penalties.total_penalty_cents = 1000`

2. **Tuesday 12:00 ET**: Run settlement
   - Verify charge is 1000 cents (sum of all days)
   - Verify `payments` record shows correct amount

**Expected Outcome:**
- User charged 1000 cents (sum of all daily penalties)
- Settlement status: `charged_actual`

---

### Scenario H: Grace Period Not Expired (Skip Settlement)

**Setup:**
1. Create commitment with `week_end_date` = Monday
2. User has NOT synced
3. Current time: Monday 12:30 ET (before Tuesday 12:00 ET)

**Test Steps:**
1. **Monday 12:30 ET**: Run settlement
   - Verify settlement detects `hasSyncedUsage = false`
   - Verify `isGracePeriodExpired = false` (grace not expired)
   - Verify settlement skips this user (`graceNotExpired += 1`)
   - Verify `user_week_penalties.settlement_status` remains `'pending'`
   - Verify NO charge occurs

**Expected Outcome:**
- No charge (grace period not expired)
- Settlement skipped
- Will charge on Tuesday 12:00 ET if still no sync

---

### Scenario I: Already Settled (Skip Duplicate Settlement)

**Setup:**
1. Complete Scenario A (user already charged actual: 450 cents)
2. Settlement status: `charged_actual`

**Test Steps:**
1. **Tuesday 12:05 ET**: Run settlement again (duplicate run)
   - Verify settlement detects `shouldSkipBecauseSettled = true`
   - Verify settlement skips this user (`alreadySettled += 1`)
   - Verify NO duplicate charge occurs
   - Verify `user_week_penalties` unchanged

**Expected Outcome:**
- No duplicate charge
- Settlement skipped (already settled)

---

### Scenario J: Missing Payment Method (Settlement Failure)

**Setup:**
1. Create commitment with `saved_payment_method_id = NULL`
2. User has synced usage

**Test Steps:**
1. **Tuesday 12:00 ET**: Run settlement
   - Verify settlement detects missing payment method
   - Verify settlement skips charge (`missingPaymentMethod += 1`)
   - Verify `user_week_penalties.settlement_status = 'charge_failed'`
   - Verify `user_week_penalties.charged_amount_cents = 0`
   - Verify NO Stripe PaymentIntent created
   - Verify error logged in summary

**Expected Outcome:**
- No charge (missing payment method)
- Settlement status: `charge_failed`
- User needs to update payment method

---

## Testing Implementation Strategy

### Phase 1: Unit Tests (Backend)

**Location**: `supabase/tests/`

**Tests to Create/Update:**
1. ✅ `test_settlement_actual.ts` - Already exists, verify it covers Scenario A
2. ✅ `test_settlement_worst_case.ts` - Already exists, verify it covers Scenario B
3. ✅ `test_late_user_refund.ts` - Already exists, verify it covers Scenario C
4. ⚠️ **NEW**: `test_settlement_capped_actual.ts` - Test Scenario E (authorization cap)
5. ⚠️ **NEW**: `test_settlement_zero_penalty.ts` - Test Scenario F (zero penalty)
6. ⚠️ **NEW**: `test_settlement_grace_period.ts` - Test Scenario H (grace period)
7. ⚠️ **NEW**: `test_settlement_already_settled.ts` - Test Scenario I (duplicate prevention)
8. ⚠️ **NEW**: `test_settlement_missing_payment_method.ts` - Test Scenario J (failure handling)

**Test Helper Functions Needed:**
- `simulateTime(dayOfWeek, hour, minute)` - Mock current time for testing
- `createCommitmentWithPaymentMethod()` - Create commitment with valid payment method
- `simulateSyncBeforeDeadline()` - Simulate user sync before Tuesday noon
- `simulateSyncAfterDeadline()` - Simulate user sync after Tuesday noon
- `runSettlementForWeek(weekEndDate)` - Run settlement for specific week
- `verifySettlementStatus(userId, weekEndDate, expectedStatus)` - Verify settlement state

### Phase 2: Integration Tests (End-to-End)

**Location**: `supabase/tests/integration/` (create if needed)

**Test Flow:**
1. Create test user with Stripe test customer
2. Create commitment with test payment method
3. Simulate usage data (daily_usage rows)
4. Simulate time progression (Monday → Tuesday)
5. Trigger sync (if testing sync-before-deadline path)
6. Run settlement
7. Verify database state
8. Verify Stripe state (if using real Stripe test mode)
9. Trigger late sync (if testing reconciliation path)
10. Run reconciliation
11. Verify final state

**Key Integration Tests:**
- `test_full_settlement_flow_sync_before_deadline.ts`
- `test_full_settlement_flow_no_sync.ts`
- `test_full_settlement_flow_late_sync_refund.ts`
- `test_full_settlement_flow_late_sync_extra_charge.ts`

### Phase 3: Manual Testing (iOS App)

**Test Environment:**
- Use staging Supabase environment
- Use Stripe test mode
- Use test user account
- Manually adjust device time (if needed) or wait for real Monday/Tuesday

**Manual Test Checklist:**

#### Test 1: Sync Before Deadline
- [ ] Create commitment in app
- [ ] Use device (trigger extension to track usage)
- [ ] Open app on Monday afternoon
- [ ] Verify sync occurs (check logs)
- [ ] Wait until Tuesday 12:00 ET
- [ ] Verify settlement runs (check database)
- [ ] Verify charge amount is actual (not worst case)
- [ ] Verify Stripe test charge created

#### Test 2: No Sync Before Deadline
- [ ] Create commitment in app
- [ ] Use device (trigger extension)
- [ ] **Do NOT open app** until after Tuesday noon
- [ ] Wait until Tuesday 12:00 ET
- [ ] Verify settlement runs
- [ ] Verify charge amount is worst case (max_charge_cents)
- [ ] Open app on Wednesday
- [ ] Verify sync occurs
- [ ] Verify reconciliation is flagged
- [ ] Run reconciliation manually
- [ ] Verify refund is issued

#### Test 3: Authorization Cap
- [ ] Create commitment with high limit (to get high authorization)
- [ ] Use device extensively (exceed authorization)
- [ ] Sync before Tuesday noon
- [ ] Verify charge is capped at authorization
- [ ] Verify actual_amount_cents shows true penalty (uncapped)

### Phase 4: Time Simulation Testing

**Challenge**: Testing time-sensitive logic without waiting for real Monday/Tuesday.

**Solutions:**

#### Option A: Mock Time in Tests
- Use dependency injection for time functions
- Mock `new Date()` in Deno tests
- Override `resolveWeekTarget()` to accept `now` parameter (already implemented!)

#### Option B: Database Time Manipulation
- Use `SET timezone = 'America/New_York'` in tests
- Use `NOW()` with timezone adjustments
- Create test commitments with specific `week_end_date` values

#### Option C: Manual Time Override
- Add `overrideWeekEndDate` parameter to settlement functions
- Use `targetWeek` parameter (already implemented in `run-weekly-settlement.ts`!)
- Test with past/future dates

**Recommended Approach**: Use Option C (already implemented) + Option A for unit tests.

---

## Test Data Setup

### Test User Creation
```typescript
const testUser = {
  id: "test-user-settlement-001",
  email: "test-settlement@example.com",
  stripe_customer_id: "cus_test_xxx", // Create in Stripe test mode
  has_active_payment_method: true,
  is_test_user: true
};
```

### Test Commitment Creation
```typescript
const testCommitment = {
  user_id: testUser.id,
  week_start_date: "2025-01-06", // Monday
  week_end_date: "2025-01-13", // Next Monday (deadline)
  limit_minutes: 60,
  penalty_per_minute_cents: 10,
  max_charge_cents: 4200, // 60 × 10 × 7
  saved_payment_method_id: "pm_test_xxx", // Create in Stripe test mode
  status: "active",
  monitoring_status: "ok"
};
```

### Test Usage Data
```typescript
const testUsage = [
  { date: "2025-01-06", used_minutes: 80, penalty_cents: 200 },
  { date: "2025-01-07", used_minutes: 75, penalty_cents: 150 },
  { date: "2025-01-08", used_minutes: 70, penalty_cents: 100 }
];
```

---

## Verification Checklist

For each test scenario, verify:

### Database State
- [ ] `commitments` table: Commitment exists with correct `max_charge_cents`
- [ ] `daily_usage` table: Usage rows created (if synced)
- [ ] `user_week_penalties` table:
  - [ ] `total_penalty_cents` = correct sum
  - [ ] `settlement_status` = expected status
  - [ ] `charged_amount_cents` = expected charge amount
  - [ ] `actual_amount_cents` = true penalty (may be uncapped)
  - [ ] `needs_reconciliation` = expected boolean
  - [ ] `reconciliation_delta_cents` = expected delta (if reconciliation needed)
- [ ] `payments` table:
  - [ ] Payment record created (if charge occurred)
  - [ ] `amount_cents` = expected amount
  - [ ] `payment_type` = expected type (`penalty_actual` or `penalty_worst_case`)
  - [ ] `status` = `succeeded` (if charge succeeded)
- [ ] `weekly_pools` table: Pool total updated correctly

### Stripe State (if using real Stripe)
- [ ] PaymentIntent created with correct amount
- [ ] PaymentIntent status = `succeeded`
- [ ] Refund created (if reconciliation refund)
- [ ] Refund amount = expected refund amount

### Edge Cases
- [ ] Zero penalty handled correctly (no charge)
- [ ] Authorization cap enforced (actual > authorization)
- [ ] Grace period respected (no charge before Tuesday noon)
- [ ] Duplicate settlement prevented (already settled)
- [ ] Missing payment method handled (charge_failed)
- [ ] Missing Stripe customer handled (charge_failed)

---

## Known Issues to Test

### Issue 1: Authorization Cap in Reconciliation
**Status**: Fixed (per TODO.md)
**Test**: Verify `rpc_sync_daily_usage` uses capped actual for reconciliation delta, not raw actual.

### Issue 2: IMMUTABLE Function Using NOW()
**Status**: Known issue (TODO.md)
**Impact**: Minor discrepancies (a few cents) between preview and commitment amounts
**Test**: Verify discrepancies are minimal and acceptable

### Issue 3: Time Zone Handling
**Status**: Should be verified
**Test**: Verify settlement runs at correct time (Tuesday 12:00 ET, not UTC)

---

## Test Execution Plan

### Step 1: Run Existing Tests
```bash
cd supabase/tests
deno test test_settlement_actual.ts --allow-net --allow-env
deno test test_settlement_worst_case.ts --allow-net --allow-env
deno test test_late_user_refund.ts --allow-net --allow-env
```

### Step 2: Create Missing Tests
Create new test files for scenarios E, F, H, I, J (see Phase 1 above).

### Step 3: Run All Tests
```bash
deno test --allow-net --allow-env --allow-read
```

### Step 4: Manual Testing
Follow manual test checklist (Phase 3 above).

### Step 5: Integration Testing
Run full end-to-end tests (Phase 2 above).

---

## Success Criteria

All tests pass when:
1. ✅ Scenario A: User syncs before Tuesday → charged actual (capped)
2. ✅ Scenario B: User doesn't sync → charged worst case
3. ✅ Scenario C: User syncs late → refund issued correctly
4. ✅ Scenario D: User syncs late with higher actual → no extra charge (capped)
5. ✅ Scenario E: Actual exceeds authorization → charge capped correctly
6. ✅ Scenario F: Zero penalty → no charge
7. ✅ Scenario G: Multiple days → sum calculated correctly
8. ✅ Scenario H: Grace period → no charge before Tuesday noon
9. ✅ Scenario I: Already settled → no duplicate charge
10. ✅ Scenario J: Missing payment method → charge_failed status

---

## Next Steps

1. **Review this strategy** with team
2. **Create missing test files** (scenarios E, F, H, I, J)
3. **Run existing tests** to verify they still pass
4. **Implement time simulation helpers** for easier testing
5. **Execute manual tests** on staging environment
6. **Document any issues** found during testing
7. **Fix issues** and re-test
8. **Sign off** on settlement process before production

---

## Appendix: Key Functions Reference

### `bright-service/run-weekly-settlement.ts`
- `resolveWeekTarget()`: Determines which week to settle
- `buildSettlementCandidates()`: Fetches commitments and usage data
- `hasSyncedUsage()`: Checks if user has synced usage
- `isGracePeriodExpired()`: Checks if grace period expired
- `getChargeAmount()`: Calculates charge amount (capped for actual)
- `chargeCandidate()`: Creates Stripe PaymentIntent

### `rpc_sync_daily_usage.sql`
- Processes batch of daily usage entries
- Calculates total penalty for week
- Detects reconciliation needs (if already settled)
- Caps actual penalty at authorization for reconciliation

### `quick-handler/settlement-reconcile`
- Processes reconciliation candidates
- Issues refunds (if delta < 0)
- Issues extra charges (if delta > 0)
- Updates settlement status

---

**End of Document**


