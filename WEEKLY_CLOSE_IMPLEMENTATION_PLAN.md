# Weekly Close Implementation Plan

## Current Status

✅ **Edge Functions Downloaded:**
- `weekly-close` - Main function (ACTIVE, version 5)
- `admin-close-week-now` - Dev tool (ACTIVE, version 2)
- `stripe-webhook` - Payment webhook handler (ACTIVE, version 3)
- `billing-status` - Billing status check (ACTIVE, version 6)

✅ **RPC Functions (Local):**
- `rpc_report_usage_fixed.sql` - Report usage
- `rpc_create_commitment_updated.sql` - Create commitment

❓ **RPC Functions (Need to Check):**
- `rpc_update_monitoring_status` - Update monitoring status
- `rpc_get_week_status` - Get week status

---

## Weekly Close Function Analysis

The `weekly-close` function (currently deployed) does:

1. ✅ **Determine last week** - Calculates week to close (7 days ago)
2. ✅ **Insert estimated rows** - For revoked monitoring commitments
3. ✅ **Recompute totals** - Updates `user_week_penalties` and `weekly_pools`
4. ✅ **Create Stripe charges** - PaymentIntents for users with balance
5. ✅ **Close weekly pool** - Marks pool as closed

**Current Implementation Notes:**
- Uses `week_start_date` to identify the week (line 36, 83, 129)
- Estimates revoked monitoring as 2x limit (double usage)
- Handles PaymentIntent statuses: succeeded, requires_action, failed, processing
- Updates both `payments` and `user_week_penalties` tables

---

## Step 1.3: Weekly Close Implementation Tasks

Based on the current `weekly-close` function, here's what Step 1.3 should cover:

### Task 1.3.1: Verify Database Schema Compatibility

**Goal:** Ensure database schema matches what `weekly-close` expects

**Check:**
- [ ] `commitments` table has: `week_start_date`, `week_end_date`, `monitoring_status`, `monitoring_revoked_at`
- [ ] `daily_usage` table has: `is_estimated`, `penalty_cents`, `exceeded_minutes`
- [ ] `user_week_penalties` table has: `week_start_date`, `total_penalty_cents`, `status`
- [ ] `weekly_pools` table has: `week_start_date`, `total_penalty_cents`, `status`, `closed_at`
- [ ] `payments` table has: `stripe_payment_intent_id`, `status`, `week_start_date`
- [ ] `users` table has: `stripe_customer_id`, `has_active_payment_method`

**Action:** Run schema verification queries

---

### Task 1.3.2: Fix Week Date Logic

**Issue:** The function uses `week_start_date` to identify weeks, but based on `REMINDER_WEEK_DATES.md`, there's confusion about:
- `week_start_date` in DB = when commitment started (current_date when user commits)
- `week_end_date` in DB = deadline (next Monday before noon)

**Current Function Logic:**
- Line 36: `eq("week_start_date", weekStartStr)` - This might not match correctly!
- The function calculates `lastWeekStartDate` as 7 days ago, but this might not align with actual commitment weeks

**Fix Needed:**
- [ ] Review how weeks are actually identified in the system
- [ ] Update function to use `week_end_date` (deadline) instead of `week_start_date` for week identification
- [ ] Or update the date calculation logic to match actual week boundaries

**Action:** Update `weekly-close/index.ts` to use correct week identification

---

### Task 1.3.3: Fix Daily Usage Aggregation

**Issue:** Line 94 queries `daily_usage` without filtering by week properly:
```typescript
const { data: userDaily } = await supabase
  .from("daily_usage")
  .select("penalty_cents, commitment_id")
  .eq("user_id", userId);
```

This gets ALL daily_usage for the user, not just for this week.

**Fix Needed:**
- [ ] Join with `commitments` table to filter by `week_end_date` (deadline)
- [ ] Or add a date range filter based on the week being closed

**Action:** Update aggregation query to properly filter by week

---

### Task 1.3.4: Verify Stripe Integration

**Check:**
- [ ] `STRIPE_SECRET_KEY` environment variable is set in Supabase
- [ ] PaymentIntent creation works correctly
- [ ] Webhook handler (`stripe-webhook`) is configured and working
- [ ] Test with a test user and test payment method

**Action:** Test Stripe payment flow

---

### Task 1.3.5: Set Up Cron Job

**Goal:** Schedule `weekly-close` to run every Monday at 12:00 EST

**Current Status:** Function exists but cron might not be configured

**Action:**
- [ ] Check if cron is configured in Supabase
- [ ] Set up scheduled function if not already done
- [ ] Test with `admin-close-week-now` first

---

### Task 1.3.6: Test Weekly Close Flow

**Test Scenarios:**
1. [ ] Week with no penalties (all users stayed within limits)
2. [ ] Week with penalties (some users exceeded limits)
3. [ ] Week with revoked monitoring (estimated penalties)
4. [ ] Week with mixed scenarios
5. [ ] PaymentIntent success case
6. [ ] PaymentIntent requires_action case
7. [ ] PaymentIntent failure case

**Action:** Create test data and run `admin-close-week-now` to test

---

## Implementation Priority

1. **HIGH:** Task 1.3.2 (Fix week date logic) - Critical for correct week identification
2. **HIGH:** Task 1.3.3 (Fix daily usage aggregation) - Critical for correct penalty calculation
3. **MEDIUM:** Task 1.3.1 (Verify schema) - Ensure everything matches
4. **MEDIUM:** Task 1.3.4 (Verify Stripe) - Ensure payments work
5. **LOW:** Task 1.3.5 (Cron setup) - Can be done after testing
6. **HIGH:** Task 1.3.6 (Testing) - Must test before going live

---

## Next Steps

1. **Review the weekly-close function** for the issues identified above
2. **Fix week date logic** (Task 1.3.2)
3. **Fix daily usage aggregation** (Task 1.3.3)
4. **Test with admin-close-week-now**
5. **Deploy fixes**
6. **Set up cron job**

---

## Questions to Answer

1. How are weeks actually identified? By `week_start_date` or `week_end_date` (deadline)?
2. What's the actual week boundary? Monday 12:00 EST?
3. Are there any existing commitments in the database to test with?
4. Is Stripe fully configured and tested?




