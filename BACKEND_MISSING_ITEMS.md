# Backend Missing Items - Based on BACKEND_BRIEFING.md

## Overview

This document compares what's required in `BACKEND_BRIEFING.md` vs what currently exists in the codebase.

---

## ✅ Phase 5: Core RPC Functions (DB Layer)

### 5.1 `rpc_create_commitment` ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `rpc_create_commitment_updated.sql` - Updated version with correct deadline logic
- `rpc_create_commitment.sql` - Original version

**Notes:**
- Function exists and has been updated to use `p_deadline_date` instead of `p_week_start_date`
- Handles payment method check, risk factor calculation, max charge calculation
- Creates weekly_pools entry if needed

**Action:** ✅ Deploy `rpc_create_commitment_updated.sql` to ensure latest version is in database

---

### 5.2 `rpc_report_usage` ✅ EXISTS
**Status:** ✅ Implemented (with fixes)  
**Files:**
- `rpc_report_usage_fixed.sql` - Fixed version
- `rpc_report_usage.sql` - Original version

**Fixes Applied:**
- ✅ Uses `week_end_date` (deadline) instead of `week_start_date` to find commitments
- ✅ Returns JSON format
- ✅ Uses INSERT ... ON CONFLICT for weekly_pools

**Action:** ✅ Deploy `rpc_report_usage_fixed.sql` to ensure latest version is in database

---

### 5.3 `rpc_update_monitoring_status` ❌ MISSING
**Status:** ❌ **NOT IMPLEMENTED**  
**Priority:** 🔴 HIGH

**Required Functionality (from BACKEND_BRIEFING.md):**
- **Inputs:**
  - `commitment_id`
  - `monitoring_status` (`ok` or `revoked`)
- **Process:**
  - Check user ownership
  - Update commitment
  - If revoked → set `monitoring_revoked_at`

**Why It's Needed:**
- iOS app needs to call this when Screen Time monitoring is revoked
- Used in Phase 10.2: "On Screen Time revocation → `rpc_update_monitoring_status`"

**Action Required:** 🔴 **CREATE THIS FUNCTION**

**Suggested Implementation:**
```sql
CREATE OR REPLACE FUNCTION public.rpc_update_monitoring_status(
  p_commitment_id uuid,
  p_monitoring_status text  -- 'ok' or 'revoked'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_commitment public.commitments;
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Fetch commitment and verify ownership
  SELECT c.*
  INTO v_commitment
  FROM public.commitments c
  WHERE c.id = p_commitment_id
    AND c.user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commitment not found or access denied' USING ERRCODE = 'P0001';
  END IF;

  -- 3) Validate status
  IF p_monitoring_status NOT IN ('ok', 'revoked') THEN
    RAISE EXCEPTION 'Invalid monitoring_status. Must be "ok" or "revoked"' USING ERRCODE = 'P0002';
  END IF;

  -- 4) Update commitment
  UPDATE public.commitments
  SET
    monitoring_status = p_monitoring_status,
    monitoring_revoked_at = CASE
      WHEN p_monitoring_status = 'revoked' THEN COALESCE(monitoring_revoked_at, NOW())
      ELSE NULL
    END,
    updated_at = NOW()
  WHERE id = p_commitment_id
    AND user_id = v_user_id;

  -- 5) Return updated commitment
  SELECT row_to_json(c.*)
  INTO v_result
  FROM public.commitments c
  WHERE c.id = p_commitment_id;

  RETURN v_result;
END;
$$;
```

---

### 5.4 `rpc_get_week_status` ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `rpc_get_week_status.sql` - Current version
- `supabase/migrations/20251117172337_rpc_get_week_status_fixed.sql` - Fixed version

**Notes:**
- Function exists and returns weekly bulletin data
- Has been fixed to use `week_end_date` (deadline) instead of `week_start_date`
- Returns: user totals, max charge, pool totals, Instagram URL + image

**Action:** ✅ Deploy fixed version to ensure latest is in database

---

## ✅ Phase 6: Edge Functions (Billing & Cron)

### 6.1 billing-status ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `supabase/functions/billing-status/billing-status.ts`

**Functionality:**
- ✅ Auth → get user
- ✅ If missing → create Stripe customer
- ✅ Check for payment method
- ✅ If none → create SetupIntent and return `client_secret`
- ✅ Updates `has_active_payment_method` flag

**Action:** ✅ Verify deployed and working

---

### 6.2 weekly-close ✅ EXISTS (Fixed)
**Status:** ✅ Implemented & Fixed  
**Files:**
- `supabase/functions/weekly-close/index.ts` - Fixed version

**Fixes Applied:**
- ✅ Uses `week_end_date` (deadline) to identify weeks
- ✅ Filters daily_usage by commitment_ids for the week
- ✅ Uses test Stripe key with fallback

**Action:** 🔴 **DEPLOY FIXED VERSION** (Critical - see COMPREHENSIVE_PLAN.md)

---

### 6.3 Cron Setup ⚠️ NEEDS VERIFICATION
**Status:** ⚠️ Script exists, but needs verification  
**Files:**
- `setup_weekly_close_cron.sql` - Setup script
- `check_cron_job_status.sql` - Verification script

**Action:** 🟡 Verify cron job is set up and active

**Note:** May require Supabase support to enable `pg_cron` extension. Alternative: Use Supabase Scheduled Functions if available.

---

## ✅ Phase 7: Stripe Webhook

### 7.1 stripe-webhook ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `supabase/functions/stripe-webhook/stripe-webhook.ts`

**Functionality:**
- ✅ Verifies `STRIPE_WEBHOOK_SECRET`
- ✅ Handles `payment_intent.succeeded`:
  - Marks payment = succeeded
  - Marks user penalties = paid
- ✅ Handles `payment_intent.payment_failed`:
  - Marks payment = failed
  - Marks user penalties = failed

**Action:** ✅ Verify webhook endpoint is configured in Stripe Dashboard

**Note:** ⚠️ Stripe webhook function uses `STRIPE_SECRET_KEY` directly - should use test key with fallback like other functions

---

## ✅ Phase 8: Security & RLS

### 8.1 RLS Policies ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `supabase/migrations/20251117200510_remote_commit.sql.backup` - Contains all RLS policies

**Policies Found:**
- ✅ `commitments`: Users can insert/read/update own commitments
- ✅ `daily_usage`: Users can insert/read/update own daily usage
- ✅ `payments`: Users can read own payments
- ✅ `usage_adjustments`: Users can read own adjustments
- ✅ `user_week_penalties`: Users can read own penalties
- ✅ `users`: Users can read/update own data
- ✅ `weekly_pools`: All authenticated users can read

**Action:** ✅ Verify all policies are active in database

---

### 8.2 Test Isolation ⚠️ NEEDS VERIFICATION
**Status:** ⚠️ Needs testing  
**Action:** 🟡 Create test account and verify no cross-user visibility

---

## ✅ Phase 9: Testing & Fast-Forward Tools

### 9.1 is_test_user ✅ EXISTS
**Status:** ✅ Column exists in `users` table  
**Action:** ✅ Verify test users are marked correctly

---

### 9.2 admin_close_week_now ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `supabase/functions/admin-close-week-now/admin-close-week-now.ts`

**Functionality:**
- ✅ Checks if user is authenticated
- ✅ Verifies user is test user (`is_test_user = true`)
- ✅ Calls `weekly-close` function
- ✅ Returns result

**Action:** ✅ Verify deployed and working

---

## ❌ Phase 10: iOS Integration

### 10.1 BackendClient.swift ✅ EXISTS
**Status:** ✅ Implemented  
**Files:**
- `payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/BackendClient.swift`

**Functions Implemented:**
- ✅ `billing-status` Edge Function call
- ✅ `rpc_create_commitment` RPC call
- ✅ `rpc_report_usage` RPC call
- ❌ `rpc_update_monitoring_status` - **MISSING** (needs to be added)
- ✅ `rpc_get_week_status` RPC call

**Action:** 🔴 **ADD `rpc_update_monitoring_status` CALL TO BackendClient.swift**

---

### 10.2 Screen Logic ✅ EXISTS (Partially)
**Status:** ⚠️ Partially implemented  
**Files:**
- Various Swift files in `payattentionclub-app-1.1/payattentionclub-app-1.1/`

**Missing:**
- ❌ Call to `rpc_update_monitoring_status` when Screen Time is revoked

**Action:** 🔴 **ADD MONITORING REVOCATION HANDLING**

---

### 10.3 Dev-only: Admin Close Week Now (iOS) ⚠️ NEEDS IMPLEMENTATION
**Status:** ⚠️ Backend exists, iOS UI missing  
**Files:**
- Backend: `supabase/functions/admin-close-week-now/` ✅
- iOS: ❌ **MISSING** - Need to add hidden dev button

**Action:** 🟡 **ADD HIDDEN DEV BUTTON TO iOS APP** (Low priority)

---

## Summary of Missing Items

### 🔴 CRITICAL (Must Have)
1. **`rpc_update_monitoring_status` RPC Function** - ❌ Missing
   - Needed for Screen Time revocation handling
   - Required for Phase 5.3

2. **Deploy Fixed `weekly-close` Function** - ⚠️ Not Deployed
   - Fixed version exists locally but needs deployment
   - Critical for weekly billing

3. **Add `rpc_update_monitoring_status` Call to BackendClient.swift** - ❌ Missing
   - iOS app needs to call this when monitoring is revoked

4. **Add Monitoring Revocation Handling in iOS App** - ❌ Missing
   - Need to detect Screen Time revocation and call RPC function

### 🟡 MEDIUM (Should Have)
5. **Verify Cron Job Setup** - ⚠️ Needs Verification
   - Script exists but needs to be verified/configured

6. **Update Stripe Webhook Function** - ⚠️ Minor Fix Needed
   - Should use test key with fallback (like other functions)

7. **Verify RLS Policies** - ⚠️ Needs Verification
   - Policies exist but should be verified in database

8. **Test Isolation** - ⚠️ Needs Testing
   - Create test account and verify no cross-user visibility

### 🟢 LOW (Nice to Have)
9. **Add Dev Button for Admin Close Week Now** - ⚠️ Missing
   - Backend exists, iOS UI missing
   - Low priority for production

---

## Recommended Action Plan

### Step 1: Create Missing RPC Function 🔴
1. Create `rpc_update_monitoring_status.sql` file
2. Deploy to database
3. Test function

### Step 2: Update iOS BackendClient 🔴
1. Add `updateMonitoringStatus()` method to `BackendClient.swift`
2. Add monitoring revocation detection in iOS app
3. Call RPC function when revocation detected

### Step 3: Deploy Fixed Functions 🔴
1. Deploy fixed `weekly-close` function
2. Deploy fixed `rpc_create_commitment_updated.sql`
3. Deploy fixed `rpc_report_usage_fixed.sql`
4. Deploy fixed `rpc_get_week_status` (if needed)

### Step 4: Verify & Test 🟡
1. Verify cron job setup
2. Test RLS policies
3. Test isolation between users
4. Update Stripe webhook function (minor fix)

### Step 5: Add Dev Tools 🟢
1. Add hidden dev button for admin-close-week-now
2. Test dev workflow

---

## Files That Need to Be Created

1. **`rpc_update_monitoring_status.sql`** - 🔴 CRITICAL
   - New RPC function for updating monitoring status

2. **Migration file for `rpc_update_monitoring_status`** - 🔴 CRITICAL
   - Add to `supabase/migrations/` folder

---

## Files That Need Updates

1. **`BackendClient.swift`** - 🔴 CRITICAL
   - Add `updateMonitoringStatus()` method

2. **iOS monitoring revocation handler** - 🔴 CRITICAL
   - Detect Screen Time revocation and call RPC

3. **`stripe-webhook/stripe-webhook.ts`** - 🟡 MEDIUM
   - Update to use test key with fallback

---

## Next Steps

1. **Create `rpc_update_monitoring_status` function** (highest priority)
2. **Add iOS integration for monitoring status updates**
3. **Deploy all fixed functions to database**
4. **Verify and test everything**

See `COMPREHENSIVE_PLAN.md` for detailed deployment and testing steps.



