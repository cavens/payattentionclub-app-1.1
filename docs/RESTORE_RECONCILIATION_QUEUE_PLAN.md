# Restoration Plan: Reconciliation Queue Logic
## Fix Missing Reconciliation Queue Insertion in `rpc_sync_daily_usage.sql`

**Date**: 2026-01-15  
**Priority**: High  
**Estimated Time**: 30-45 minutes

---

## Problem Summary

The reconciliation queue insertion logic was removed from `rpc_sync_daily_usage.sql` between commit `0552a75` (Jan 13) and commit `3568118` (Jan 15). This breaks automatic reconciliation for late syncs.

**Current State**:
- ✅ Reconciliation delta calculation exists
- ✅ `needs_reconciliation` flag is set correctly
- ❌ **Queue insertion logic is missing** - reconciliations aren't queued
- ❌ `V_STRIPE_MINIMUM_CENTS` constant missing
- ❌ `v_prev_payment_intent_id` variable missing
- ❌ `v_prev_needs_reconciliation` variable missing

**Impact**: Late syncs won't automatically trigger reconciliation processing.

---

## Solution Plan

### Step 1: Add Missing Variables and Constants

**Location**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`  
**Section**: DECLARE block (around line 7-32)

**Changes**:
1. Add `v_prev_payment_intent_id text;` variable
2. Add `v_prev_needs_reconciliation boolean;` variable  
3. Add `V_STRIPE_MINIMUM_CENTS CONSTANT integer := 60;` constant

**Code to Add**:
```sql
DECLARE
  v_user_id uuid := auth.uid();
  v_entry jsonb;
  v_date date;
  v_week_start_date date;
  v_used_minutes integer;
  v_commitment_id uuid;
  v_limit_minutes integer;
  v_penalty_per_minute_cents integer;
  v_exceeded_minutes integer;
  v_penalty_cents integer;
  v_synced_dates text[] := ARRAY[]::text[];
  v_failed_dates text[] := ARRAY[]::text[];
  v_errors text[] := ARRAY[]::text[];
  v_user_week_total_cents integer;
  v_pool_total_cents integer;
  v_result json;
  v_processed_weeks date[] := ARRAY[]::date[];
  v_week date;
  v_prev_settlement_status text;
  v_prev_charged_amount integer;
  v_prev_payment_intent_id text;  -- ✅ ADD THIS
  v_prev_needs_reconciliation boolean;  -- ✅ ADD THIS
  v_needs_reconciliation boolean;
  v_reconciliation_delta integer;
  v_max_charge_cents integer;
  v_capped_actual_cents integer;
  V_SETTLED_STATUSES CONSTANT text[] := ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial'];
  V_STRIPE_MINIMUM_CENTS CONSTANT integer := 60;  -- ✅ ADD THIS (Stripe minimum charge, matches bright-service)
```

---

### Step 2: Update SELECT Query to Fetch Additional Fields

**Location**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`  
**Section**: Around line 140-150 (where we fetch previous settlement status)

**Current Code** (lines 138-150):
```sql
      v_prev_settlement_status := NULL;
      v_prev_charged_amount := 0;
      BEGIN
        SELECT settlement_status, COALESCE(charged_amount_cents, 0)
        INTO v_prev_settlement_status, v_prev_charged_amount
        FROM public.user_week_penalties
        WHERE user_id = v_user_id
          AND week_start_date = v_week;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_prev_settlement_status := NULL;
          v_prev_charged_amount := 0;
      END;
```

**Replace With**:
```sql
      v_prev_settlement_status := NULL;
      v_prev_charged_amount := 0;
      v_prev_payment_intent_id := NULL;
      v_prev_needs_reconciliation := false;
      BEGIN
        SELECT 
          settlement_status, 
          COALESCE(charged_amount_cents, 0), 
          charge_payment_intent_id,
          COALESCE(needs_reconciliation, false)
        INTO 
          v_prev_settlement_status, 
          v_prev_charged_amount, 
          v_prev_payment_intent_id,
          v_prev_needs_reconciliation
        FROM public.user_week_penalties
        WHERE user_id = v_user_id
          AND week_start_date = v_week;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_prev_settlement_status := NULL;
          v_prev_charged_amount := 0;
          v_prev_payment_intent_id := NULL;
          v_prev_needs_reconciliation := false;
      END;
```

---

### Step 3: Enhance Reconciliation Delta Logic (Optional but Recommended)

**Location**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`  
**Section**: Around line 166-174 (reconciliation delta calculation)

**Current Code** (lines 166-174):
```sql
      v_needs_reconciliation := false;
      v_reconciliation_delta := 0;
      IF v_prev_settlement_status = ANY(V_SETTLED_STATUSES) THEN
        -- Use capped actual for reconciliation delta (not raw actual)
        v_reconciliation_delta := v_capped_actual_cents - COALESCE(v_prev_charged_amount, 0);
        IF v_reconciliation_delta <> 0 THEN
          v_needs_reconciliation := true;
        END IF;
      END IF;
```

**Replace With** (includes below-minimum handling from commit `0552a75`):
```sql
      v_needs_reconciliation := false;
      v_reconciliation_delta := 0;
      IF v_prev_settlement_status = ANY(V_SETTLED_STATUSES) THEN
        -- Special case: If previous charge was 0 due to below-minimum, and current actual is also below minimum,
        -- skip reconciliation (we can't charge the actual amount anyway, so no change is needed)
        IF v_prev_charged_amount = 0 
           AND v_prev_payment_intent_id IN ('below_minimum', 'zero_amount')
           AND v_capped_actual_cents < V_STRIPE_MINIMUM_CENTS THEN
          -- Both previous charge and current actual are below minimum - no reconciliation needed
          v_reconciliation_delta := 0;
          v_needs_reconciliation := false;
        ELSE
          -- Use capped actual for reconciliation delta (not raw actual)
          v_reconciliation_delta := v_capped_actual_cents - COALESCE(v_prev_charged_amount, 0);
          IF v_reconciliation_delta <> 0 THEN
            v_needs_reconciliation := true;
          END IF;
        END IF;
      END IF;
```

**Note**: This handles the edge case where both the previous charge and current actual are below Stripe's $0.60 minimum, avoiding unnecessary reconciliation attempts.

---

### Step 4: Add Reconciliation Queue Insertion Logic

**Location**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`  
**Section**: After the `INSERT INTO public.user_week_penalties` statement (around line 220), before the `weekly_pools` INSERT

**Insert After** (line 220, after `last_updated = NOW();`):
```sql
      -- The queue will be processed by a cron job that can use pg_net (which works in cron context)
      IF v_needs_reconciliation AND NOT v_prev_needs_reconciliation THEN
        BEGIN
          -- Log that we're queuing reconciliation
          RAISE NOTICE 'Queuing automatic reconciliation for user % week % (delta: % cents)', 
            v_user_id, v_week, v_reconciliation_delta;

          -- Insert into reconciliation queue (will be processed by cron job)
          -- Use ON CONFLICT to handle race conditions (multiple syncs at once)
          -- The partial unique index ensures only one pending entry per user/week
          INSERT INTO public.reconciliation_queue (
            user_id,
            week_start_date,
            reconciliation_delta_cents,
            status,
            created_at
          )
          VALUES (
            v_user_id,
            v_week,
            v_reconciliation_delta,
            'pending',
            NOW()
          )
          ON CONFLICT (user_id, week_start_date) 
          WHERE status = 'pending'
          DO UPDATE SET
            reconciliation_delta_cents = EXCLUDED.reconciliation_delta_cents,
            created_at = EXCLUDED.created_at,
            retry_count = 0; -- Reset retry count if re-queued
          
          RAISE NOTICE '✅ Reconciliation queued successfully for user % week %', 
            v_user_id, v_week;
        EXCEPTION
          WHEN OTHERS THEN
            -- Don't fail the sync if queue insert fails
            -- The reconciliation can be triggered manually later if needed
            RAISE WARNING '❌ Failed to queue reconciliation for user % week %: %', 
              v_user_id, v_week, SQLERRM;
        END;
      ELSE
        -- Log why reconciliation wasn't triggered (for debugging)
        IF v_needs_reconciliation THEN
          RAISE NOTICE 'Reconciliation needed but not triggered: prev_needs_reconciliation=% (already flagged)', v_prev_needs_reconciliation;
        END IF;
      END IF;
```

**Important Notes**:
- This code only queues reconciliation when `v_needs_reconciliation` is `true` AND `v_prev_needs_reconciliation` is `false`
- This prevents duplicate queue entries if reconciliation was already flagged
- Uses `ON CONFLICT` to handle race conditions (multiple syncs happening simultaneously)
- Wrapped in `BEGIN...EXCEPTION` so queue insert failures don't break the sync operation

---

## Verification Steps

### 1. Check Reconciliation Queue Table Exists

**Query**:
```sql
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'reconciliation_queue'
);
```

**Expected**: Should return `true`

**If Missing**: Check if migration `20260111220000_create_reconciliation_queue.sql` exists and was applied.

---

### 2. Verify Function Compiles

**Query**:
```sql
SELECT pg_get_functiondef('public.rpc_sync_daily_usage'::regproc);
```

**Expected**: Should return the function definition without errors

---

### 3. Test Reconciliation Queue Insertion

**Test Scenario**: User syncs late (after settlement has run)

**Steps**:
1. Create a commitment and let it settle (charge worst case)
2. Sync usage data that results in a different penalty amount
3. Check if reconciliation was queued:

```sql
SELECT * FROM public.reconciliation_queue 
WHERE user_id = '<test_user_id>' 
ORDER BY created_at DESC 
LIMIT 1;
```

**Expected**: Should see a row with:
- `status = 'pending'`
- `reconciliation_delta_cents` = difference between actual and charged amount
- `created_at` = recent timestamp

---

### 4. Verify Queue Processing

**Check if cron job exists**:
```sql
SELECT * FROM cron.job WHERE jobname LIKE '%reconcile%';
```

**Expected**: Should see a cron job that processes the reconciliation queue

**If Missing**: May need to set up the cron job (check `process_reconciliation_queue.sql` RPC and cron setup)

---

## Testing Checklist

- [ ] Function compiles without errors
- [ ] Variables and constants added correctly
- [ ] SELECT query fetches all required fields
- [ ] Reconciliation delta calculation includes below-minimum handling
- [ ] Queue insertion logic executes when reconciliation is needed
- [ ] Queue insertion doesn't break sync if it fails
- [ ] No duplicate queue entries created (ON CONFLICT works)
- [ ] Logging messages appear in function logs
- [ ] End-to-end test: late sync → queue entry → cron processes it

---

## Risk Assessment

### Low Risk ✅
- Adding variables and constants (no functional change)
- Updating SELECT query (just fetching more data)

### Medium Risk ⚠️
- Enhancing reconciliation delta logic (handles edge case, shouldn't break existing flow)
- Adding queue insertion (wrapped in exception handler, won't break sync)

### Mitigation
- All queue insertion code is wrapped in `BEGIN...EXCEPTION` block
- Queue insert failures only log warnings, don't fail the sync
- `ON CONFLICT` handles race conditions
- Can be tested in staging before production

---

## Rollback Plan

If issues arise:

1. **Quick Rollback**: Remove the queue insertion block (Step 4)
   - Function will still calculate reconciliation deltas
   - Just won't queue them automatically
   - Manual reconciliation via `quick-handler` still works

2. **Full Rollback**: Revert to current version
   - Git revert the changes
   - Re-apply function from current state

---

## Files to Modify

1. **`supabase/remote_rpcs/rpc_sync_daily_usage.sql`**
   - Add variables and constants (Step 1)
   - Update SELECT query (Step 2)
   - Enhance reconciliation logic (Step 3, optional)
   - Add queue insertion (Step 4)

**Total Changes**: ~70 lines added/modified

---

## Dependencies

### Required
- ✅ `reconciliation_queue` table exists (from migration `20260111220000_create_reconciliation_queue.sql`)
- ✅ `reconciliation_queue` has unique constraint on `(user_id, week_start_date)` where `status = 'pending'`
- ✅ `reconciliation_queue` has `retry_count` column

### Optional (for full functionality)
- ✅ Cron job to process reconciliation queue
- ✅ `process_reconciliation_queue` RPC function (if exists)

---

## Next Steps After Restoration

1. **Test in staging environment**
2. **Verify queue processing works** (if cron job exists)
3. **Monitor logs** for reconciliation queue insertions
4. **Document** any issues or edge cases found
5. **Consider** adding integration test for late sync → queue → processing flow

---

## Questions to Verify Before Implementation

1. **Does `reconciliation_queue` table exist in production?**
   - Check migration status
   - Verify table schema matches expected structure

2. **Is there a cron job to process the queue?**
   - Check `cron.job` table
   - Verify `process_reconciliation_queue` function exists

3. **Should we restore the below-minimum handling logic?**
   - Commit `0552a75` had this logic
   - Current version doesn't have it
   - **Recommendation**: Yes, restore it (Step 3)

4. **Are there any other differences between commit and current?**
   - Review full diff if needed
   - Check for any other missing logic

---

## Summary

**What We're Restoring**:
1. ✅ Missing variables (`v_prev_payment_intent_id`, `v_prev_needs_reconciliation`)
2. ✅ Missing constant (`V_STRIPE_MINIMUM_CENTS`)
3. ✅ Enhanced SELECT query to fetch additional fields
4. ✅ Below-minimum handling logic (optional but recommended)
5. ✅ **Reconciliation queue insertion logic** (critical)

**Impact**: Restores automatic reconciliation queueing for late syncs, enabling automatic refunds/charges without manual intervention.

**Risk**: Low - all changes are additive, queue insertion is wrapped in exception handler.

**Time Estimate**: 30-45 minutes (including testing)


