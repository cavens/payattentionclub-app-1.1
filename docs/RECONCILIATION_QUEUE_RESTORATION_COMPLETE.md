# Reconciliation Queue Infrastructure - Restoration Complete

**Date**: 2026-01-15  
**Status**: ✅ **COMPLETE**

---

## Summary

All reconciliation queue infrastructure has been successfully restored from commit `0552a75`. This restores the complete automatic reconciliation flow for late syncs.

---

## Files Restored/Created

### 1. ✅ Table Migration
**File**: `supabase/migrations/20260111220000_create_reconciliation_queue.sql`

**Contents**:
- Creates `reconciliation_queue` table
- Creates indexes for fast polling and unique constraints
- Sets up RLS policies
- Adds table and column comments

**Status**: ✅ Created

---

### 2. ✅ RPC Function
**File**: `supabase/remote_rpcs/process_reconciliation_queue.sql`

**Contents**:
- Processes pending reconciliation queue entries
- Calls `quick-handler` Edge Function via `pg_net.http_post()`
- Handles retries (max 3 attempts)
- Marks entries as completed or failed
- Respects TESTING_MODE from app_config

**Status**: ✅ Created

---

### 3. ✅ Cron Job Setup
**File**: `supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql`

**Contents**:
- Sets up two cron jobs:
  - Testing mode: Every 1 minute (`process-reconciliation-queue-testing`)
  - Normal mode: Every 10 minutes (`process-reconciliation-queue-normal`)
- Both jobs call `process_reconciliation_queue()` function
- Function checks TESTING_MODE and only processes if it matches

**Status**: ✅ Created

---

### 4. ✅ Queue Insertion Logic
**File**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`

**Changes Made**:

1. **Added Missing Variables** (DECLARE block):
   - `v_prev_payment_intent_id text;`
   - `v_prev_needs_reconciliation boolean;`

2. **Added Missing Constant**:
   - `V_STRIPE_MINIMUM_CENTS CONSTANT integer := 60;`

3. **Enhanced SELECT Query** (lines 141-160):
   - Now fetches `charge_payment_intent_id` and `needs_reconciliation` from previous penalty record
   - Initializes all variables in EXCEPTION handler

4. **Enhanced Reconciliation Logic** (lines 181-200):
   - Added below-minimum handling:
     - If previous charge was 0 due to below-minimum AND current actual is also below minimum
     - Skip reconciliation (no change needed)
   - Otherwise, calculate reconciliation delta as before

5. **Added Queue Insertion Logic** (lines 247-290):
   - Inserts into `reconciliation_queue` when:
     - `v_needs_reconciliation = true` AND
     - `v_prev_needs_reconciliation = false` (prevents duplicate entries)
   - Uses `ON CONFLICT` to handle race conditions
   - Wrapped in exception handler (won't break sync if queue insert fails)
   - Logs success/failure messages

**Status**: ✅ Updated

---

## Complete Flow

### Automatic Reconciliation Flow

1. **User syncs late** (after Tuesday noon, after settlement has run)
   - `rpc_sync_daily_usage` processes the sync
   - Calculates actual penalty amount
   - Detects reconciliation needed (delta between actual and charged)

2. **Queue insertion** (in `rpc_sync_daily_usage`)
   - If reconciliation needed AND not already flagged:
     - Inserts entry into `reconciliation_queue` table
     - Status: `pending`
     - Logs: "Queuing automatic reconciliation"

3. **Cron job processes queue** (every 1 min in testing, 10 min in normal)
   - `process_reconciliation_queue()` function runs
   - Finds pending entries (oldest first, limit 10 per run)
   - Marks entry as `processing`
   - Calls `quick-handler` Edge Function via `pg_net.http_post()`
   - Marks entry as `completed` or `failed`

4. **Quick-handler processes reconciliation**
   - Finds users with `needs_reconciliation = true`
   - Calculates refund or additional charge
   - Processes via Stripe
   - Updates `user_week_penalties` record

---

## Next Steps

### 1. Apply Migrations

**In Staging/Production**:
```bash
# Apply table migration
supabase migration up 20260111220000_create_reconciliation_queue

# Apply cron setup migration
supabase migration up 20260111220100_setup_reconciliation_queue_cron
```

**Or via Supabase Dashboard**:
- Go to Database → Migrations
- Apply both migrations

---

### 2. Verify RPC Function

**Check function exists**:
```sql
SELECT pg_get_functiondef('public.process_reconciliation_queue'::regproc);
```

**Expected**: Should return the function definition

---

### 3. Verify Cron Jobs

**Check cron jobs exist**:
```sql
SELECT * FROM cron.job 
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal');
```

**Expected**: Should see 2 jobs with correct schedules

---

### 4. Test End-to-End Flow

**Test Scenario**: Late sync after settlement

1. Create commitment and let it settle (charge worst case)
2. Sync usage data that results in different penalty amount
3. Check queue entry created:
   ```sql
   SELECT * FROM public.reconciliation_queue 
   WHERE user_id = '<test_user_id>' 
   ORDER BY created_at DESC 
   LIMIT 1;
   ```
4. Wait for cron job to process (1 min in testing, 10 min in normal)
5. Check queue entry processed:
   ```sql
   SELECT status, processed_at FROM public.reconciliation_queue 
   WHERE id = '<queue_entry_id>';
   ```
6. Verify reconciliation completed:
   ```sql
   SELECT needs_reconciliation, reconciliation_delta_cents, settlement_status
   FROM public.user_week_penalties
   WHERE user_id = '<test_user_id>' AND week_start_date = '<week>';
   ```

---

## Verification Checklist

- [x] Table migration file created
- [x] RPC function file created
- [x] Cron setup migration file created
- [x] Queue insertion logic added to `rpc_sync_daily_usage.sql`
- [x] Missing variables added
- [x] Missing constant added
- [x] Enhanced SELECT query
- [x] Enhanced reconciliation logic (below-minimum handling)
- [ ] Migrations applied to database
- [ ] RPC function verified in database
- [ ] Cron jobs verified in database
- [ ] End-to-end test completed

---

## Important Notes

### Queue Insertion Logic

- **Only queues when**: `v_needs_reconciliation = true` AND `v_prev_needs_reconciliation = false`
- **Prevents duplicates**: Uses unique index on `(user_id, week_start_date)` where `status = 'pending'`
- **Race condition safe**: Uses `ON CONFLICT` to handle concurrent syncs
- **Error handling**: Wrapped in exception handler, won't break sync if queue insert fails

### Cron Job Behavior

- **Testing mode**: Runs every 1 minute (fast processing)
- **Normal mode**: Runs every 10 minutes (efficient)
- **Function checks TESTING_MODE**: Only processes if mode matches
- **Limit**: Processes up to 10 entries per run (oldest first)

### Below-Minimum Handling

- **Special case**: If both previous charge and current actual are below Stripe minimum ($0.60)
- **Action**: Skip reconciliation (no change needed, can't charge below minimum anyway)
- **Prevents**: Unnecessary reconciliation attempts for amounts that can't be charged

---

## Rollback Plan

If issues arise:

1. **Remove queue insertion logic** from `rpc_sync_daily_usage.sql`
   - Reconciliation detection still works
   - Just won't queue automatically
   - Manual reconciliation via `quick-handler` still works

2. **Disable cron jobs**:
   ```sql
   SELECT cron.unschedule(jobid) 
   FROM cron.job 
   WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal');
   ```

3. **Full rollback**: Revert all 4 files to previous state

---

## Summary

✅ **All reconciliation queue infrastructure has been restored**

**Files Created/Updated**:
1. ✅ `supabase/migrations/20260111220000_create_reconciliation_queue.sql` (new)
2. ✅ `supabase/remote_rpcs/process_reconciliation_queue.sql` (new)
3. ✅ `supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql` (new)
4. ✅ `supabase/remote_rpcs/rpc_sync_daily_usage.sql` (updated)

**Next**: Apply migrations and test end-to-end flow.


