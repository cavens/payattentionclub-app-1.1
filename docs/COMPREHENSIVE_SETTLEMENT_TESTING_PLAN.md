# Comprehensive Settlement Testing Plan

**Status**: 📋 Planning  
**Priority**: High  
**Date**: 2026-01-19

## Overview

This document outlines a comprehensive testing plan for the settlement process covering all reasonable scenarios. The plan tests 3 main cases, each with 2 sub-conditions, across 4 different usage patterns, resulting in **24 total test cases**.

---

## Test Matrix Structure

### 3 Main Cases
1. **Case 1**: Sync within the grace period
2. **Case 2**: No sync within the grace period
3. **Case 3**: Late sync (after grace period expires)

### 2 Sub-Conditions (per main case)
- **(1) Sync before grace period begins**: User syncs data before the grace period starts (should not affect settlement since data is incomplete)
- **(2) No sync before grace period begins**: User does not sync before grace period starts

### 4 Usage Patterns (per sub-condition)
- **Pattern A**: 0 usage of limited apps AND 0 penalty (user did not use any limited apps)
- **Pattern B**: >0 usage of limited apps AND <60 cent penalty (below Stripe minimum)
- **Pattern C**: >0 usage of limited apps AND >60 cent penalty (actual penalty that will get processed/paid)
- **Pattern D**: >0 usage of limited apps AND 0 penalty (user used the limited apps but did not cross the time limit)

**Total: 3 × 2 × 4 = 24 test cases**

---

## Timeline Reference (Testing Mode)

- **Week Deadline**: T+0 minutes (week_end_date)
- **Grace Period Begins**: T+0 minutes (immediately after deadline)
- **Grace Period Expires**: T+1 minute (1 minute after deadline)
- **Settlement Runs**: T+1 minute (when grace expires)

**Note**: In testing mode, syncing "before grace period begins" means syncing before T+0 (before the deadline), which should not affect settlement since the week's data is incomplete.

---

## Test Case Naming Convention

Format: `Case{MainCase}_{SubCondition}_{UsagePattern}`

- **MainCase**: 1, 2, or 3
- **SubCondition**: A (sync before grace begins) or B (no sync before grace begins)
- **UsagePattern**: A, B, C, or D

Example: `Case1_A_C` = Case 1, Sync before grace begins, Pattern C (>60 cent penalty)

---

## Test Cases

### Case 1: Sync Within Grace Period

#### Case 1_A_A: Sync Before Grace Begins + 0 Usage + 0 Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 0 minutes of limited apps
- Penalty: 0 cents

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Sync again within grace period (T+0.5 minutes) with complete week data
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `no_charge` or `pending` (zero penalty)
- Charged amount: 0 cents
- No Stripe PaymentIntent created
- No payment record created

**Verification:**
- `user_week_penalties.total_penalty_cents = 0`
- `user_week_penalties.settlement_status = 'no_charge'` or `'pending'`
- `user_week_penalties.charged_amount_cents = 0`
- No `payments` record

---

#### Case 1_A_B: Sync Before Grace Begins + >0 Usage + <60 Cent Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 5 minutes over limit (e.g., 65 minutes used, 60 minute limit)
- Penalty: 50 cents (below Stripe minimum)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Sync again within grace period (T+0.5 minutes) with complete week data showing 50 cent penalty
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `no_charge` or `pending` (below Stripe minimum)
- Charged amount: 0 cents (Stripe minimum not met)
- No Stripe PaymentIntent created
- No payment record created

**Verification:**
- `user_week_penalties.total_penalty_cents = 50`
- `user_week_penalties.settlement_status = 'no_charge'` or `'pending'`
- `user_week_penalties.charged_amount_cents = 0`
- No `payments` record

---

#### Case 1_A_C: Sync Before Grace Begins + >0 Usage + >60 Cent Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 20 minutes over limit
- Penalty: 200 cents (above Stripe minimum)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Sync again within grace period (T+0.5 minutes) with complete week data showing 200 cent penalty
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_actual`
- Charged amount: 200 cents (actual penalty, capped at authorization if needed)
- Stripe PaymentIntent created with 200 cents
- Payment record created with `payment_type = 'penalty_actual'`

**Verification:**
- `user_week_penalties.total_penalty_cents = 200`
- `user_week_penalties.settlement_status = 'charged_actual'`
- `user_week_penalties.charged_amount_cents = 200`
- `user_week_penalties.actual_amount_cents = 200`
- `payments` record exists with `amount_cents = 200`

---

#### Case 1_A_D: Sync Before Grace Begins + >0 Usage + 0 Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 50 minutes of limited apps (under 60 minute limit)
- Penalty: 0 cents (did not exceed limit)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Sync again within grace period (T+0.5 minutes) with complete week data showing 0 penalty
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `no_charge` or `pending` (zero penalty)
- Charged amount: 0 cents
- No Stripe PaymentIntent created
- No payment record created

**Verification:**
- `user_week_penalties.total_penalty_cents = 0`
- `user_week_penalties.settlement_status = 'no_charge'` or `'pending'`
- `user_week_penalties.charged_amount_cents = 0`
- No `payments` record

---

#### Case 1_B_A: No Sync Before Grace Begins + 0 Usage + 0 Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 0 minutes of limited apps
- Penalty: 0 cents

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Sync within grace period (T+0.5 minutes) with complete week data showing 0 usage
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `no_charge` or `pending` (zero penalty)
- Charged amount: 0 cents
- No Stripe PaymentIntent created
- No payment record created

**Verification:**
- `user_week_penalties.total_penalty_cents = 0`
- `user_week_penalties.settlement_status = 'no_charge'` or `'pending'`
- `user_week_penalties.charged_amount_cents = 0`
- No `payments` record

---

#### Case 1_B_B: No Sync Before Grace Begins + >0 Usage + <60 Cent Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 5 minutes over limit
- Penalty: 50 cents (below Stripe minimum)

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Sync within grace period (T+0.5 minutes) with complete week data showing 50 cent penalty
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `no_charge` or `pending` (below Stripe minimum)
- Charged amount: 0 cents
- No Stripe PaymentIntent created
- No payment record created

**Verification:**
- `user_week_penalties.total_penalty_cents = 50`
- `user_week_penalties.settlement_status = 'no_charge'` or `'pending'`
- `user_week_penalties.charged_amount_cents = 0`
- No `payments` record

---

#### Case 1_B_C: No Sync Before Grace Begins + >0 Usage + >60 Cent Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 20 minutes over limit
- Penalty: 200 cents (above Stripe minimum)

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Sync within grace period (T+0.5 minutes) with complete week data showing 200 cent penalty
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_actual`
- Charged amount: 200 cents (actual penalty, capped at authorization if needed)
- Stripe PaymentIntent created with 200 cents
- Payment record created with `payment_type = 'penalty_actual'`

**Verification:**
- `user_week_penalties.total_penalty_cents = 200`
- `user_week_penalties.settlement_status = 'charged_actual'`
- `user_week_penalties.charged_amount_cents = 200`
- `user_week_penalties.actual_amount_cents = 200`
- `payments` record exists with `amount_cents = 200`

---

#### Case 1_B_D: No Sync Before Grace Begins + >0 Usage + 0 Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 50 minutes of limited apps (under limit)
- Penalty: 0 cents

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Sync within grace period (T+0.5 minutes) with complete week data showing 0 penalty
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `no_charge` or `pending` (zero penalty)
- Charged amount: 0 cents
- No Stripe PaymentIntent created
- No payment record created

**Verification:**
- `user_week_penalties.total_penalty_cents = 0`
- `user_week_penalties.settlement_status = 'no_charge'` or `'pending'`
- `user_week_penalties.charged_amount_cents = 0`
- No `payments` record

---

### Case 2: No Sync Within Grace Period

#### Case 2_A_A: Sync Before Grace Begins + 0 Usage + 0 Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 0 minutes of limited apps
- Penalty: 0 cents
- User does NOT sync within grace period

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case` or `no_charge` (if 0 usage = 0 worst case)
- Charged amount: `max_charge_cents` (worst case) OR 0 if no usage
- If `max_charge_cents > 0`: Stripe PaymentIntent created
- If `max_charge_cents > 0`: Payment record created with `payment_type = 'penalty_worst_case'`

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'` or `'no_charge'`
- `user_week_penalties.charged_amount_cents = max_charge_cents` (or 0 if no usage)
- `user_week_penalties.actual_amount_cents = 0` (unknown at charge time)

**Note**: If user has 0 usage, worst case should also be 0. This tests the edge case.

---

#### Case 2_A_B: Sync Before Grace Begins + >0 Usage + <60 Cent Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 5 minutes over limit
- Penalty: 50 cents (below Stripe minimum)
- User does NOT sync within grace period

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case`
- Charged amount: `max_charge_cents` (worst case, since no sync within grace)
- Stripe PaymentIntent created with `max_charge_cents`
- Payment record created with `payment_type = 'penalty_worst_case'`

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'`
- `user_week_penalties.charged_amount_cents = max_charge_cents`
- `user_week_penalties.actual_amount_cents = 0` (unknown at charge time)
- `user_week_penalties.needs_reconciliation = true` (will need reconciliation when user syncs)
- `payments` record exists with `amount_cents = max_charge_cents`

---

#### Case 2_A_C: Sync Before Grace Begins + >0 Usage + >60 Cent Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 20 minutes over limit
- Penalty: 200 cents (above Stripe minimum)
- User does NOT sync within grace period

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case`
- Charged amount: `max_charge_cents` (worst case, since no sync within grace)
- Stripe PaymentIntent created with `max_charge_cents`
- Payment record created with `payment_type = 'penalty_worst_case'`

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'`
- `user_week_penalties.charged_amount_cents = max_charge_cents`
- `user_week_penalties.actual_amount_cents = 0` (unknown at charge time)
- `user_week_penalties.needs_reconciliation = true` (will need reconciliation when user syncs)
- `payments` record exists with `amount_cents = max_charge_cents`

---

#### Case 2_A_D: Sync Before Grace Begins + >0 Usage + 0 Penalty
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 50 minutes of limited apps (under limit)
- Penalty: 0 cents
- User does NOT sync within grace period

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case` or `no_charge`
- Charged amount: `max_charge_cents` (worst case) OR 0 if worst case is 0
- If `max_charge_cents > 0`: Stripe PaymentIntent created
- If `max_charge_cents > 0`: Payment record created

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'` or `'no_charge'`
- `user_week_penalties.charged_amount_cents = max_charge_cents` (or 0)

**Note**: If user stayed within limit, worst case might be 0 or might be based on potential overage.

---

#### Case 2_B_A: No Sync Before Grace Begins + 0 Usage + 0 Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 0 minutes of limited apps
- Penalty: 0 cents
- User does NOT sync within grace period

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case` or `no_charge`
- Charged amount: `max_charge_cents` (worst case) OR 0 if no usage
- If `max_charge_cents > 0`: Stripe PaymentIntent created
- If `max_charge_cents > 0`: Payment record created

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'` or `'no_charge'`
- `user_week_penalties.charged_amount_cents = max_charge_cents` (or 0)

---

#### Case 2_B_B: No Sync Before Grace Begins + >0 Usage + <60 Cent Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 5 minutes over limit
- Penalty: 50 cents (below Stripe minimum)
- User does NOT sync within grace period

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case`
- Charged amount: `max_charge_cents` (worst case)
- Stripe PaymentIntent created with `max_charge_cents`
- Payment record created with `payment_type = 'penalty_worst_case'`

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'`
- `user_week_penalties.charged_amount_cents = max_charge_cents`
- `user_week_penalties.actual_amount_cents = 0` (unknown at charge time)
- `user_week_penalties.needs_reconciliation = true`
- `payments` record exists with `amount_cents = max_charge_cents`

---

#### Case 2_B_C: No Sync Before Grace Begins + >0 Usage + >60 Cent Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 20 minutes over limit
- Penalty: 200 cents (above Stripe minimum)
- User does NOT sync within grace period

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case`
- Charged amount: `max_charge_cents` (worst case)
- Stripe PaymentIntent created with `max_charge_cents`
- Payment record created with `payment_type = 'penalty_worst_case'`

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'`
- `user_week_penalties.charged_amount_cents = max_charge_cents`
- `user_week_penalties.actual_amount_cents = 0` (unknown at charge time)
- `user_week_penalties.needs_reconciliation = true`
- `payments` record exists with `amount_cents = max_charge_cents`

---

#### Case 2_B_D: No Sync Before Grace Begins + >0 Usage + 0 Penalty
**Setup:**
- User does NOT sync before deadline
- Usage: 50 minutes of limited apps (under limit)
- Penalty: 0 cents
- User does NOT sync within grace period

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to begin (T+0)
3. Do NOT sync within grace period
4. Wait for grace period to expire (T+1 minute)
5. Trigger settlement

**Expected Results:**
- Settlement status: `charged_worst_case` or `no_charge`
- Charged amount: `max_charge_cents` (worst case) OR 0
- If `max_charge_cents > 0`: Stripe PaymentIntent created
- If `max_charge_cents > 0`: Payment record created

**Verification:**
- `user_week_penalties.settlement_status = 'charged_worst_case'` or `'no_charge'`
- `user_week_penalties.charged_amount_cents = max_charge_cents` (or 0)

---

### Case 3: Late Sync (After Grace Period Expires)

#### Case 3_A_A: Sync Before Grace Begins + 0 Usage + 0 Penalty + Late Sync
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 0 minutes of limited apps
- Penalty: 0 cents
- Settlement charged worst case (or 0)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case or 0)
4. Sync late (T+2 minutes) with complete week data showing 0 usage

**Expected Results:**
- Reconciliation delta: 0 cents (if worst case was 0) OR negative (if worst case > 0)
- If delta < 0: Refund issued
- If delta = 0: No reconciliation needed
- Settlement status: `refunded` or `refunded_partial` (if refund) OR `charged_worst_case` (if no change)

**Verification:**
- `user_week_penalties.needs_reconciliation = false` (if delta = 0) OR `true` (if delta != 0)
- `user_week_penalties.reconciliation_delta_cents = expected_delta`
- If refund: `user_week_penalties.refund_amount_cents = refund_amount`
- If refund: `payments` record with `payment_type = 'penalty_refund'`

---

#### Case 3_A_B: Sync Before Grace Begins + >0 Usage + <60 Cent Penalty + Late Sync
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 5 minutes over limit
- Penalty: 50 cents (below Stripe minimum)
- Settlement charged worst case (`max_charge_cents`)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case)
4. Sync late (T+2 minutes) with complete week data showing 50 cent penalty

**Expected Results:**
- Reconciliation delta: `50 - max_charge_cents` (negative, refund needed)
- Refund issued for difference
- Settlement status: `refunded` or `refunded_partial`

**Verification:**
- `user_week_penalties.needs_reconciliation = true` (initially)
- `user_week_penalties.reconciliation_delta_cents = 50 - max_charge_cents`
- After reconciliation: `user_week_penalties.settlement_status = 'refunded'` or `'refunded_partial'`
- `user_week_penalties.refund_amount_cents = max_charge_cents - 50`
- `payments` record with `payment_type = 'penalty_refund'`

**Note**: Since actual penalty (50 cents) is below Stripe minimum, final charge should be 0, so full refund of worst case.

---

#### Case 3_A_C: Sync Before Grace Begins + >0 Usage + >60 Cent Penalty + Late Sync
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 20 minutes over limit
- Penalty: 200 cents (above Stripe minimum)
- Settlement charged worst case (`max_charge_cents`)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case)
4. Sync late (T+2 minutes) with complete week data showing 200 cent penalty

**Expected Results:**
- Reconciliation delta: `200 - max_charge_cents`
- If delta < 0: Refund issued
- If delta > 0: Extra charge issued (if under cap)
- If delta = 0: No reconciliation needed
- Settlement status: `refunded`, `refunded_partial`, `charged_actual_adjusted`, or `charged_worst_case` (unchanged)

**Verification:**
- `user_week_penalties.needs_reconciliation = true` (if delta != 0)
- `user_week_penalties.reconciliation_delta_cents = 200 - max_charge_cents`
- After reconciliation: Status updated appropriately
- If refund: `user_week_penalties.refund_amount_cents = refund_amount`
- If extra charge: Additional payment record created

---

#### Case 3_A_D: Sync Before Grace Begins + >0 Usage + 0 Penalty + Late Sync
**Setup:**
- User syncs before deadline (T-1 minute)
- Usage: 50 minutes of limited apps (under limit)
- Penalty: 0 cents
- Settlement charged worst case (`max_charge_cents`)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Sync usage before deadline (T-1 minute)
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case)
4. Sync late (T+2 minutes) with complete week data showing 0 penalty

**Expected Results:**
- Reconciliation delta: `0 - max_charge_cents` (negative, full refund)
- Full refund issued
- Settlement status: `refunded` or `refunded_partial`

**Verification:**
- `user_week_penalties.needs_reconciliation = true`
- `user_week_penalties.reconciliation_delta_cents = -max_charge_cents`
- After reconciliation: `user_week_penalties.settlement_status = 'refunded'`
- `user_week_penalties.refund_amount_cents = max_charge_cents`
- `payments` record with `payment_type = 'penalty_refund'`

---

#### Case 3_B_A: No Sync Before Grace Begins + 0 Usage + 0 Penalty + Late Sync
**Setup:**
- User does NOT sync before deadline
- Usage: 0 minutes of limited apps
- Penalty: 0 cents
- Settlement charged worst case (or 0)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case or 0)
4. Sync late (T+2 minutes) with complete week data showing 0 usage

**Expected Results:**
- Reconciliation delta: 0 cents (if worst case was 0) OR negative (if worst case > 0)
- If delta < 0: Refund issued
- If delta = 0: No reconciliation needed

**Verification:**
- `user_week_penalties.needs_reconciliation = false` (if delta = 0) OR `true` (if delta != 0)
- `user_week_penalties.reconciliation_delta_cents = expected_delta`
- If refund: `user_week_penalties.refund_amount_cents = refund_amount`

---

#### Case 3_B_B: No Sync Before Grace Begins + >0 Usage + <60 Cent Penalty + Late Sync
**Setup:**
- User does NOT sync before deadline
- Usage: 5 minutes over limit
- Penalty: 50 cents (below Stripe minimum)
- Settlement charged worst case (`max_charge_cents`)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case)
4. Sync late (T+2 minutes) with complete week data showing 50 cent penalty

**Expected Results:**
- Reconciliation delta: `50 - max_charge_cents` (negative, refund needed)
- Refund issued for difference
- Settlement status: `refunded` or `refunded_partial`

**Verification:**
- `user_week_penalties.needs_reconciliation = true`
- `user_week_penalties.reconciliation_delta_cents = 50 - max_charge_cents`
- After reconciliation: `user_week_penalties.settlement_status = 'refunded'` or `'refunded_partial'`
- `user_week_penalties.refund_amount_cents = max_charge_cents - 50`
- `payments` record with `payment_type = 'penalty_refund'`

---

#### Case 3_B_C: No Sync Before Grace Begins + >0 Usage + >60 Cent Penalty + Late Sync
**Setup:**
- User does NOT sync before deadline
- Usage: 20 minutes over limit
- Penalty: 200 cents (above Stripe minimum)
- Settlement charged worst case (`max_charge_cents`)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case)
4. Sync late (T+2 minutes) with complete week data showing 200 cent penalty

**Expected Results:**
- Reconciliation delta: `200 - max_charge_cents`
- If delta < 0: Refund issued
- If delta > 0: Extra charge issued (if under cap)
- If delta = 0: No reconciliation needed
- Settlement status: `refunded`, `refunded_partial`, `charged_actual_adjusted`, or `charged_worst_case` (unchanged)

**Verification:**
- `user_week_penalties.needs_reconciliation = true` (if delta != 0)
- `user_week_penalties.reconciliation_delta_cents = 200 - max_charge_cents`
- After reconciliation: Status updated appropriately
- If refund: `user_week_penalties.refund_amount_cents = refund_amount`
- If extra charge: Additional payment record created

---

#### Case 3_B_D: No Sync Before Grace Begins + >0 Usage + 0 Penalty + Late Sync
**Setup:**
- User does NOT sync before deadline
- Usage: 50 minutes of limited apps (under limit)
- Penalty: 0 cents
- Settlement charged worst case (`max_charge_cents`)
- User syncs late (after T+1 minute)

**Test Steps:**
1. Do NOT sync before deadline
2. Wait for grace period to expire (T+1 minute)
3. Trigger settlement (charges worst case)
4. Sync late (T+2 minutes) with complete week data showing 0 penalty

**Expected Results:**
- Reconciliation delta: `0 - max_charge_cents` (negative, full refund)
- Full refund issued
- Settlement status: `refunded` or `refunded_partial`

**Verification:**
- `user_week_penalties.needs_reconciliation = true`
- `user_week_penalties.reconciliation_delta_cents = -max_charge_cents`
- After reconciliation: `user_week_penalties.settlement_status = 'refunded'`
- `user_week_penalties.refund_amount_cents = max_charge_cents`
- `payments` record with `payment_type = 'penalty_refund'`

---

## Test Execution Checklist

### Pre-Test Setup
- [ ] Enable testing mode (`TESTING_MODE=true`)
- [ ] Clear all test data
- [ ] Verify test user exists with valid payment method
- [ ] Verify commitment exists with appropriate settings
- [ ] Note the `max_charge_cents` value for worst case scenarios

### For Each Test Case
- [ ] Set up usage data according to pattern
- [ ] Execute sync actions according to sub-condition
- [ ] Wait for appropriate timeline milestones
- [ ] Trigger settlement (if applicable)
- [ ] Trigger late sync (if Case 3)
- [ ] Trigger reconciliation (if Case 3)
- [ ] Verify all database state
- [ ] Verify Stripe state (if applicable)
- [ ] Document results
- [ ] Clear test data before next case

### Post-Test Cleanup
- [ ] Clear all test data
- [ ] Disable testing mode (if desired)
- [ ] Review all test results
- [ ] Document any issues found

---

## Key Verification Points

### Database Tables to Check

1. **`commitments`**
   - `max_charge_cents` (for worst case calculations)
   - `limit_minutes`
   - `penalty_per_minute_cents`

2. **`daily_usage`**
   - Usage rows created (if synced)
   - `minutes_used` matches test pattern
   - `penalty_cents` matches test pattern

3. **`user_week_penalties`**
   - `total_penalty_cents` = sum of daily penalties
   - `settlement_status` = expected status
   - `charged_amount_cents` = expected charge
   - `actual_amount_cents` = true penalty (may be uncapped)
   - `needs_reconciliation` = expected boolean
   - `reconciliation_delta_cents` = expected delta
   - `refund_amount_cents` = expected refund (if applicable)

4. **`payments`**
   - Payment record created (if charge occurred)
   - `amount_cents` = expected amount
   - `payment_type` = expected type
   - `status` = `succeeded` (if charge succeeded)

### Stripe State (if using real Stripe)
- PaymentIntent created with correct amount
- PaymentIntent status = `succeeded`
- Refund created (if reconciliation refund)
- Refund amount = expected refund amount

---

## Special Considerations

### Stripe Minimum Charge
- Stripe minimum is 50-60 cents (varies by country)
- Penalties below this minimum should not be charged
- Settlement should skip charges below minimum

### Authorization Cap
- Actual penalty may exceed `max_charge_cents` (authorization)
- Charges should be capped at authorization amount
- Reconciliation should use capped actual, not raw actual

### Zero Penalty Handling
- Zero penalty should result in no charge
- Status should be `no_charge` or `pending`
- No Stripe PaymentIntent should be created

### Grace Period Logic
- Syncing before grace period begins should not affect settlement
- Only syncing within grace period matters for Case 1
- No sync within grace period triggers Case 2

### Reconciliation Logic
- Reconciliation delta = capped_actual - charged_amount
- If delta < 0: Refund
- If delta > 0: Extra charge (if under cap)
- If delta = 0: No reconciliation needed

---

## Test Case Summary Table

| Case | Sub-Condition | Usage Pattern | Description | Expected Status |
|------|---------------|---------------|-------------|-----------------|
| 1_A_A | Sync before grace | 0 usage, 0 penalty | Sync before + within grace, no usage | `no_charge` |
| 1_A_B | Sync before grace | >0 usage, <60¢ penalty | Sync before + within grace, below min | `no_charge` |
| 1_A_C | Sync before grace | >0 usage, >60¢ penalty | Sync before + within grace, actual charge | `charged_actual` |
| 1_A_D | Sync before grace | >0 usage, 0 penalty | Sync before + within grace, under limit | `no_charge` |
| 1_B_A | No sync before grace | 0 usage, 0 penalty | No sync before + within grace, no usage | `no_charge` |
| 1_B_B | No sync before grace | >0 usage, <60¢ penalty | No sync before + within grace, below min | `no_charge` |
| 1_B_C | No sync before grace | >0 usage, >60¢ penalty | No sync before + within grace, actual charge | `charged_actual` |
| 1_B_D | No sync before grace | >0 usage, 0 penalty | No sync before + within grace, under limit | `no_charge` |
| 2_A_A | Sync before grace | 0 usage, 0 penalty | Sync before + no sync within grace, no usage | `charged_worst_case` or `no_charge` |
| 2_A_B | Sync before grace | >0 usage, <60¢ penalty | Sync before + no sync within grace, below min | `charged_worst_case` |
| 2_A_C | Sync before grace | >0 usage, >60¢ penalty | Sync before + no sync within grace, actual | `charged_worst_case` |
| 2_A_D | Sync before grace | >0 usage, 0 penalty | Sync before + no sync within grace, under limit | `charged_worst_case` or `no_charge` |
| 2_B_A | No sync before grace | 0 usage, 0 penalty | No sync before + no sync within grace, no usage | `charged_worst_case` or `no_charge` |
| 2_B_B | No sync before grace | >0 usage, <60¢ penalty | No sync before + no sync within grace, below min | `charged_worst_case` |
| 2_B_C | No sync before grace | >0 usage, >60¢ penalty | No sync before + no sync within grace, actual | `charged_worst_case` |
| 2_B_D | No sync before grace | >0 usage, 0 penalty | No sync before + no sync within grace, under limit | `charged_worst_case` or `no_charge` |
| 3_A_A | Sync before grace | 0 usage, 0 penalty | Late sync after worst case charge, no usage | `refunded` or `charged_worst_case` |
| 3_A_B | Sync before grace | >0 usage, <60¢ penalty | Late sync after worst case, below min | `refunded` |
| 3_A_C | Sync before grace | >0 usage, >60¢ penalty | Late sync after worst case, actual | `refunded`/`charged_actual_adjusted` |
| 3_A_D | Sync before grace | >0 usage, 0 penalty | Late sync after worst case, under limit | `refunded` |
| 3_B_A | No sync before grace | 0 usage, 0 penalty | Late sync after worst case, no usage | `refunded` or `charged_worst_case` |
| 3_B_B | No sync before grace | >0 usage, <60¢ penalty | Late sync after worst case, below min | `refunded` |
| 3_B_C | No sync before grace | >0 usage, >60¢ penalty | Late sync after worst case, actual | `refunded`/`charged_actual_adjusted` |
| 3_B_D | No sync before grace | >0 usage, 0 penalty | Late sync after worst case, under limit | `refunded` |

---

## Next Steps

1. **Review this plan** with team
2. **Set up test data generation** for each usage pattern
3. **Create test execution scripts** to automate test cases
4. **Execute tests** systematically
5. **Document results** for each test case
6. **Fix any issues** found during testing
7. **Re-test** after fixes
8. **Sign off** on settlement process before production

---

## Notes

- All test cases assume testing mode is enabled (compressed timeline)
- Timeline: T+0 = deadline, T+1 = grace expires
- Stripe minimum: 50-60 cents (test with 50 cents to be safe)
- Authorization cap: `max_charge_cents` from commitment
- Reconciliation uses capped actual, not raw actual

