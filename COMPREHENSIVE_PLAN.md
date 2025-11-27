# 📋 Comprehensive Project Plan - What's Next

## Current Status Summary

### ✅ Completed
1. **Weekly Close Function Fixed** - All critical bugs fixed:
   - ✅ Week identification now uses `week_end_date` (deadline) instead of `week_start_date`
   - ✅ Daily usage aggregation now filters by commitment_ids for the week
   - ✅ Stripe key uses test key with fallback to production
   - ✅ Deadline calculation logic fixed (handles Monday, Sunday, Tue-Sat correctly)

2. **Code Committed** - All changes committed and pushed to remote repository

3. **Documentation Created** - Extensive documentation for:
   - Testing procedures
   - Function verification
   - Cron job setup
   - Database state checking

### ⚠️ Needs Action
1. **Deploy Fixed Function** - Local fixes need to be deployed to Supabase
2. **Test Weekly Close** - Function needs to be tested with real/test data
3. **Set Up Cron Job** - Automated weekly execution needs to be configured
4. **Verify Database State** - Ensure schema matches function expectations
5. **Test iOS App** - End-to-end app testing needs to be performed

---

## Phase 1: Deploy & Verify Weekly Close Function 🔴 HIGH PRIORITY

### Task 1.1: Deploy Fixed weekly-close Function
**Status:** ⚠️ Not Deployed  
**Priority:** 🔴 CRITICAL

**Actions:**
1. Deploy the fixed `supabase/functions/weekly-close/index.ts` to Supabase
   - Use Supabase CLI: `supabase functions deploy weekly-close`
   - Or use Supabase Dashboard → Functions → weekly-close → Deploy

**Verification:**
- [ ] Function deployed successfully
- [ ] Check function logs for any deployment errors
- [ ] Verify function version incremented in Supabase Dashboard

**Files:**
- `supabase/functions/weekly-close/index.ts` (already fixed locally)

---

### Task 1.2: Verify Function Deployment
**Status:** ⚠️ Not Verified  
**Priority:** 🔴 CRITICAL

**Actions:**
1. Run verification SQL script: `verify_function_fixed.sql`
2. Check that function exists and is active
3. Verify no placeholder values remain

**Verification:**
- [ ] Function exists in database
- [ ] Function definition matches local version
- [ ] No placeholders (YOUR_PROJECT, YOUR_SERVICE_ROLE_KEY) found

**Files:**
- `verify_function_fixed.sql`

---

### Task 1.3: Test Weekly Close Function
**Status:** ⚠️ Not Tested  
**Priority:** 🔴 CRITICAL

**Actions:**
1. **Set up test data** (if needed):
   - Use `rpc_setup_test_data.sql` or `cleanup_and_setup_test_data.sql`
   - Create test commitments with `week_end_date` matching a test deadline
   - Add test daily_usage records

2. **Run function via Supabase Dashboard:**
   - Go to Functions → weekly-close → Invoke
   - Method: POST
   - Body: `{}`
   - Check response and logs

3. **Verify results:**
   - Check `weekly_pools` table was updated
   - Check `user_week_penalties` table was updated
   - Check `payments` table (if penalties exist)
   - Verify correct week was closed (check `weekDeadline` in response)

**Test Scenarios:**
- [ ] Week with no commitments (should return empty results)
- [ ] Week with commitments but no penalties (all users stayed within limits)
- [ ] Week with penalties (some users exceeded limits)
- [ ] Week with revoked monitoring (estimated penalties should be created)
- [ ] Week with mixed scenarios

**Files:**
- `HOW_TO_TEST_WEEKLY_CLOSE_DIRECT.md`
- `rpc_setup_test_data.sql`
- `cleanup_and_setup_test_data.sql`
- `check_specific_week.sql`

---

## Phase 2: Database Verification & Setup 🔴 HIGH PRIORITY

### Task 2.1: Verify Database Schema
**Status:** ⚠️ Not Verified  
**Priority:** 🔴 CRITICAL

**Actions:**
1. Run schema verification queries to ensure all required tables/columns exist:
   - `commitments` table: `week_start_date`, `week_end_date`, `monitoring_status`, `monitoring_revoked_at`
   - `daily_usage` table: `is_estimated`, `penalty_cents`, `exceeded_minutes`, `commitment_id`
   - `user_week_penalties` table: `week_start_date`, `total_penalty_cents`, `status`
   - `weekly_pools` table: `week_start_date`, `total_penalty_cents`, `status`, `closed_at`
   - `payments` table: `stripe_payment_intent_id`, `status`, `week_start_date`
   - `users` table: `stripe_customer_id`, `has_active_payment_method`

**Verification:**
- [ ] All required tables exist
- [ ] All required columns exist with correct types
- [ ] Indexes are in place (unique constraints)
- [ ] Foreign key relationships are correct

**Files:**
- `check_db_state.sql` (may need to create comprehensive schema check)

---

### Task 2.2: Verify RPC Functions Exist
**Status:** ⚠️ Not Verified  
**Priority:** 🟡 MEDIUM

**Actions:**
1. Check if required RPC functions exist in database:
   - `rpc_report_usage` (or `rpc_report_usage_fixed`)
   - `rpc_create_commitment` (or `rpc_create_commitment_updated`)
   - `rpc_get_week_status` (check if exists)
   - `rpc_update_monitoring_status` (check if exists)

2. Deploy missing RPC functions from migration files:
   - `supabase/migrations/20251117170250_rpc_setup_test_data.sql`
   - `supabase/migrations/20251117172337_rpc_get_week_status_fixed.sql`

**Verification:**
- [ ] All required RPC functions exist
- [ ] Functions match local versions
- [ ] Functions are callable and return expected results

**Files:**
- `check_function_exists.sql`
- `rpc_report_usage_fixed.sql`
- `rpc_create_commitment_updated.sql`
- `rpc_get_week_status.sql`

---

## Phase 3: Cron Job Setup 🟡 MEDIUM PRIORITY

### Task 3.1: Set Up Weekly Close Cron Job
**Status:** ⚠️ Not Configured  
**Priority:** 🟡 MEDIUM (can be done after testing)

**Actions:**
1. **Check if cron extension is enabled:**
   - Run: `SELECT * FROM pg_extension WHERE extname = 'pg_cron';`
   - If not enabled, enable it (may require Supabase support)

2. **Check if cron job already exists:**
   - Run: `check_cron_job_status.sql`
   - Look for job named `pac_weekly_close_job` or `weekly-close-monday`

3. **Create cron job if needed:**
   - Run: `setup_weekly_close_cron.sql`
   - Schedule: Every Monday at 12:00 EST (17:00 UTC)
   - Verify job was created and is active

**Verification:**
- [ ] Cron extension is enabled
- [ ] Cron job exists and is active
- [ ] Schedule is correct (Monday 17:00 UTC)
- [ ] Job points to correct function URL

**Files:**
- `setup_weekly_close_cron.sql`
- `check_cron_job_status.sql`
- `verify_cron_setup.sql`

**Note:** Cron jobs may require Supabase support to enable `pg_cron` extension. Alternative: Use Supabase Edge Functions scheduled invocations (if available).

---

## Phase 4: Stripe Integration Verification 🟡 MEDIUM PRIORITY

### Task 4.1: Verify Stripe Configuration
**Status:** ⚠️ Not Verified  
**Priority:** 🟡 MEDIUM

**Actions:**
1. **Check Stripe environment variables in Supabase:**
   - `STRIPE_SECRET_KEY_TEST` (should be set for testing)
   - `STRIPE_SECRET_KEY` (production key)
   - Verify keys are set in Supabase Dashboard → Settings → Edge Functions → Secrets

2. **Test Stripe webhook:**
   - Verify `stripe-webhook` function is deployed
   - Check webhook endpoint is configured in Stripe Dashboard
   - Test webhook with test events

3. **Test payment flow:**
   - Create test user with Stripe customer ID
   - Run weekly-close with test data that creates penalties
   - Verify PaymentIntent is created correctly
   - Check payment status updates in database

**Verification:**
- [ ] Stripe keys are configured in Supabase
- [ ] Webhook endpoint is configured in Stripe
- [ ] PaymentIntent creation works
- [ ] Payment status updates correctly

**Files:**
- `add_test_user_with_stripe.sql`
- `HOW_TO_TEST_ADMIN_CLOSE.md`

---

## Phase 5: iOS App Testing 🟢 LOW PRIORITY (After Backend Works)

### Task 5.1: Test App Flow
**Status:** ⚠️ Not Tested  
**Priority:** 🟢 LOW (can wait until backend is stable)

**Actions:**
1. **Build and run app:**
   - Open Xcode project
   - Clean build folder (Shift + Cmd + K)
   - Build and run on device (Cmd + R)

2. **Test complete flow:**
   - Loading screen → Setup screen
   - Create commitment (select apps, set limits)
   - Grant Screen Time access
   - Complete authorization (Stripe payment)
   - Monitor screen shows countdown
   - Use selected apps and verify usage tracking

3. **Verify usage reporting:**
   - Use apps for >1 minute
   - Check Console.app for MonitorExtension logs
   - Verify usage appears in MonitorView
   - Check database for `daily_usage` records

**Verification:**
- [ ] App builds and runs
- [ ] Full flow works end-to-end
- [ ] Usage tracking works correctly
- [ ] Data syncs to database

**Files:**
- `NEXT_STEPS_TESTING.md`
- `HOW_TO_TEST_APP_USAGE.md`
- `HOW_TO_SEE_LOGS.md`

---

## Phase 6: Production Readiness 🔵 FUTURE

### Task 6.1: Production Deployment Checklist
**Status:** 🔵 Not Started  
**Priority:** 🔵 FUTURE

**Actions:**
1. **Environment setup:**
   - [ ] Create production Supabase project
   - [ ] Set up production Stripe account
   - [ ] Configure production environment variables
   - [ ] Set up production cron jobs

2. **Security review:**
   - [ ] Review RLS policies
   - [ ] Verify service role key is not exposed
   - [ ] Check API rate limiting
   - [ ] Review error handling

3. **Monitoring:**
   - [ ] Set up error tracking (Sentry, etc.)
   - [ ] Set up logging aggregation
   - [ ] Create alerts for failed weekly closes
   - [ ] Monitor payment failures

4. **Documentation:**
   - [ ] Update production deployment guide
   - [ ] Document operational procedures
   - [ ] Create runbook for common issues

---

## Priority Summary

### 🔴 CRITICAL (Do First)
1. **Deploy fixed weekly-close function** (Task 1.1)
2. **Verify function deployment** (Task 1.2)
3. **Test weekly close function** (Task 1.3)
4. **Verify database schema** (Task 2.1)

### 🟡 MEDIUM (Do Next)
5. **Verify RPC functions** (Task 2.2)
6. **Set up cron job** (Task 3.1)
7. **Verify Stripe configuration** (Task 4.1)

### 🟢 LOW (Can Wait)
8. **Test iOS app** (Task 5.1)

### 🔵 FUTURE
9. **Production deployment** (Task 6.1)

---

## Recommended Next Steps (Immediate)

### 🔴 CRITICAL - Missing Backend Function

1. **Deploy `rpc_update_monitoring_status` function** (NEWLY CREATED)
   - File: `rpc_update_monitoring_status.sql` or migration `20251118000000_rpc_update_monitoring_status.sql`
   - This function is required for Screen Time revocation handling
   - See `BACKEND_MISSING_ITEMS.md` for details

2. **Deploy the fixed weekly-close function** to Supabase
   ```bash
   supabase functions deploy weekly-close
   ```

3. **Test the function** using Supabase Dashboard:
   - Functions → weekly-close → Invoke → POST with `{}`

4. **Verify the results**:
   - Check function logs
   - Check database tables (`weekly_pools`, `user_week_penalties`)
   - Verify correct week was identified

5. **Set up test data** (if needed) and run more comprehensive tests

6. **Set up cron job** once function is verified to work correctly

### 🟡 iOS Integration Needed

7. **Add `rpc_update_monitoring_status` call to BackendClient.swift**
   - See `BACKEND_MISSING_ITEMS.md` for details

8. **Add monitoring revocation detection in iOS app**
   - Detect when Screen Time monitoring is revoked
   - Call `rpc_update_monitoring_status` when detected

---

## Questions to Answer

1. **Is the fixed function already deployed?** (Check Supabase Dashboard)
2. **Are there any test commitments in the database?** (Run `check_db_state.sql`)
3. **Is pg_cron extension enabled?** (May need Supabase support)
4. **Are Stripe keys configured?** (Check Supabase secrets)
5. **What's the current week's deadline?** (Check `commitments` table for `week_end_date`)

---

## Notes

- All fixes have been applied locally and committed to git
- The weekly-close function is ready to deploy
- Testing should be done before setting up cron job
- iOS app testing can wait until backend is stable
- Production deployment is a separate phase

---

## Files Reference

### Key Files to Use:
- `supabase/functions/weekly-close/index.ts` - Fixed function (deploy this)
- `verify_function_fixed.sql` - Verify deployment
- `HOW_TO_TEST_WEEKLY_CLOSE_DIRECT.md` - Testing guide
- `setup_weekly_close_cron.sql` - Cron setup
- `check_cron_job_status.sql` - Check cron status
- `rpc_setup_test_data.sql` - Create test data
- `check_db_state.sql` - Verify database state

### Status Files:
- `WEEKLY_CLOSE_FIXES_APPLIED.md` - What was fixed
- `WEEKLY_CLOSE_FIXES_NEEDED.md` - Original issues (now fixed)
- `WEEKLY_CLOSE_STATUS.md` - Overall status
- `WEEKLY_CLOSE_IMPLEMENTATION_PLAN.md` - Original plan

