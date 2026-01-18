# Next Steps After Applying Migrations

**Date**: 2026-01-17  
**Status**: Migrations Applied ✅

---

## Step 1: Verify Setup

Run the verification queries to ensure everything is set up correctly:

**File**: `docs/VERIFY_RECONCILIATION_QUEUE_SETUP.sql`

Or run this quick check:

```sql
-- Quick Health Check
SELECT 
  'Table exists' AS check_name,
  EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reconciliation_queue') AS status
UNION ALL
SELECT 
  'Process function exists' AS check_name,
  EXISTS (SELECT FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'process_reconciliation_queue') AS status
UNION ALL
SELECT 
  'Sync function has queue logic' AS check_name,
  EXISTS (SELECT FROM information_schema.routines WHERE routine_schema = 'public' AND routine_name = 'rpc_sync_daily_usage' AND routine_definition LIKE '%reconciliation_queue%') AS status
UNION ALL
SELECT 
  'Cron jobs exist' AS check_name,
  (SELECT COUNT(*) FROM cron.job WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')) = 2 AS status;
```

**Expected**: All 4 checks should return `status = true`

---

## Step 2: Test End-to-End Flow

### Test Scenario: Late Sync After Settlement

**Goal**: Verify that late syncs automatically trigger reconciliation via the queue.

**Steps**:

1. **Create a commitment** (if you don't have one)
   - Use your iOS app or create via SQL
   - Make sure it has a valid payment method

2. **Let it settle** (or manually trigger settlement)
   - Wait for Tuesday noon (normal mode) or grace period (testing mode)
   - Or manually trigger: `SELECT bright_service.run_weekly_settlement();`
   - This should charge the user (worst case or actual)

3. **Sync usage data late** (after settlement)
   - Use your iOS app to sync usage
   - Or manually call `rpc_sync_daily_usage` with usage data that results in a different penalty amount
   - This should create a reconciliation queue entry

4. **Check queue entry was created**:
   ```sql
   SELECT * FROM public.reconciliation_queue 
   WHERE user_id = '<your_user_id>' 
   ORDER BY created_at DESC 
   LIMIT 1;
   ```
   **Expected**: Should see a row with `status = 'pending'` and `reconciliation_delta_cents` set

5. **Wait for cron to process** (or trigger manually):
   - **Testing mode**: Wait 1 minute
   - **Normal mode**: Wait 10 minutes
   - **Or trigger manually**:
     ```sql
     SELECT public.process_reconciliation_queue();
     ```

6. **Check queue entry was processed**:
   ```sql
   SELECT status, processed_at, error_message 
   FROM public.reconciliation_queue 
   WHERE id = '<queue_entry_id>';
   ```
   **Expected**: `status = 'completed'` and `processed_at` is set

7. **Verify reconciliation completed**:
   ```sql
   SELECT 
     needs_reconciliation,
     reconciliation_delta_cents,
     settlement_status,
     charged_amount_cents,
     actual_amount_cents
   FROM public.user_week_penalties
   WHERE user_id = '<your_user_id>' 
     AND week_start_date = '<week_start_date>';
   ```
   **Expected**: Reconciliation should be processed (refund or additional charge made)

---

## Step 3: Monitor Logs

### Check Supabase Logs

1. Go to Supabase Dashboard → Logs
2. Look for:
   - `process_reconciliation_queue` function calls
   - `quick-handler` Edge Function calls
   - Any errors related to reconciliation

### Check for Queue Processing

```sql
-- See recent queue activity
SELECT 
  id,
  user_id,
  week_start_date,
  reconciliation_delta_cents,
  status,
  created_at,
  processed_at,
  error_message,
  retry_count
FROM public.reconciliation_queue
ORDER BY created_at DESC
LIMIT 10;
```

---

## Step 4: Verify in Both Environments

### Staging
- ✅ Migrations applied
- ✅ Verification queries pass
- ✅ End-to-end test works

### Production
- ⏳ Apply migrations (when ready)
- ⏳ Run verification queries
- ⏳ Monitor for first real reconciliation

---

## Common Issues & Troubleshooting

### Issue: Queue entries not being created

**Check**:
- Is `rpc_sync_daily_usage` updated? (should have queue insertion logic)
- Are you syncing after settlement has run?
- Check function logs for errors

**Debug**:
```sql
-- Check if sync function has queue logic
SELECT routine_definition 
FROM information_schema.routines 
WHERE routine_name = 'rpc_sync_daily_usage'
AND routine_definition LIKE '%reconciliation_queue%';
```

---

### Issue: Queue entries not being processed

**Check**:
- Are cron jobs active?
  ```sql
  SELECT jobid, jobname, active FROM cron.job 
  WHERE jobname LIKE '%reconcile%';
  ```
- Is `process_reconciliation_queue` function working?
  ```sql
  SELECT public.process_reconciliation_queue();
  ```
- Check for errors in queue entries:
  ```sql
  SELECT * FROM reconciliation_queue WHERE status = 'failed';
  ```

---

### Issue: Reconciliation not completing

**Check**:
- Is `quick-handler` Edge Function working?
- Are Stripe credentials configured?
- Check `quick-handler` logs in Supabase Dashboard

---

## Success Criteria

✅ All verification queries pass  
✅ Queue entries are created when late syncs happen  
✅ Cron jobs process queue entries automatically  
✅ Reconciliation completes successfully (refunds/charges processed)  
✅ No errors in logs  

---

## Summary

**What's Now Working**:
- ✅ Late syncs automatically queue reconciliation requests
- ✅ Cron jobs process queue entries automatically
- ✅ Reconciliation happens without manual intervention

**Next**: Test the end-to-end flow and monitor for any issues!


