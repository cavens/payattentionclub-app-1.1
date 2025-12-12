# Phase 6: Verification Guide

## Overview

This guide helps you verify that Phase 6 (Cron Jobs) is fully set up and working correctly.

## Step 1: Verify Cron Jobs Are Scheduled

### Via Dashboard

**Staging:**
1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/database/cron
2. You should see 3 cron jobs:
   - `weekly-close-staging` - Monday 17:00 UTC
   - `Weekly-Settlement` - Tuesday 12:00 UTC
   - `settlement-reconcile` - Every 6 hours

**Production:**
1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/database/cron
2. You should see 3 cron jobs:
   - `weekly-close-production` - Monday 17:00 UTC
   - `Weekly-Settlement` - Tuesday 12:00 UTC
   - `settlement-reconcile` - Every 6 hours

### Via Script

```bash
# List all cron jobs
./scripts/run_sql_via_api.sh staging "SELECT jobid, jobname, schedule, active FROM cron.job ORDER BY jobid;"
./scripts/run_sql_via_api.sh production "SELECT jobid, jobname, schedule, active FROM cron.job ORDER BY jobid;"
```

Or use the RPC function:
```bash
# Via curl (requires jq for pretty printing)
curl -X POST "${STAGING_SUPABASE_URL}/rest/v1/rpc/rpc_list_cron_jobs" \
  -H "apikey: ${STAGING_SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${STAGING_SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" | jq .
```

## Step 2: Check Edge Function Logs

### Staging - weekly-close

1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs
2. Look for recent invocations (from our test calls)
3. Check for:
   - ✅ Successful HTTP 200 responses
   - ✅ No error messages
   - ✅ Log entries showing the function executed

### Production - weekly-close

1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs
2. Look for recent invocations
3. Check for successful execution

### Other Edge Functions

**bright-service (Weekly-Settlement):**
- Staging: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/bright-service/logs
- Production: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/bright-service/logs

**quick-handler (settlement-reconcile):**
- Staging: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/quick-handler/logs
- Production: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/quick-handler/logs

## Step 3: Test Functions Manually

### Test call_weekly_close()

**Staging:**
```sql
SELECT public.call_weekly_close();
```

**Production:**
```sql
SELECT public.call_weekly_close();
```

Then check the Edge Function logs to verify it was called.

### Test via Script

```bash
# Test staging
./scripts/run_sql_via_api.sh staging "SELECT public.call_weekly_close();"

# Test production
./scripts/run_sql_via_api.sh production "SELECT public.call_weekly_close();"
```

## Step 4: Verify Service Role Key

Check that the service role key is set in `_internal_config`:

**Staging:**
```sql
SELECT key, LEFT(value, 20) || '...' as value_preview, updated_at
FROM public._internal_config
WHERE key = 'service_role_key';
```

**Production:**
```sql
SELECT key, LEFT(value, 20) || '...' as value_preview, updated_at
FROM public._internal_config
WHERE key = 'service_role_key';
```

## Step 5: Check Cron Job History

### Via Dashboard

1. Go to **Database → Cron Jobs**
2. Click on a cron job
3. View execution history
4. Check for:
   - ✅ Successful runs
   - ⚠️ Failed runs (if any)
   - 📅 Next scheduled run

### Via SQL

```sql
-- Check recent cron job runs
SELECT 
    j.jobid,
    j.jobname,
    jrd.runid,
    jrd.start_time,
    jrd.end_time,
    jrd.status,
    jrd.return_message
FROM cron.job j
LEFT JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
WHERE j.jobname LIKE 'weekly-close%'
ORDER BY jrd.start_time DESC
LIMIT 10;
```

## Step 6: Monitor First Scheduled Run

### Weekly Close

- **Schedule:** Every Monday at 17:00 UTC (12:00 PM EST / 1:00 PM EDT)
- **Next Run:** Calculate next Monday at 17:00 UTC
- **What to Check:**
  - Edge Function logs show invocation
  - No errors in logs
  - Database tables updated (weekly_pools, user_week_penalties, payments)

### Weekly Settlement

- **Schedule:** Every Tuesday at 12:00 UTC
- **Next Run:** Calculate next Tuesday at 12:00 UTC
- **What to Check:**
  - bright-service Edge Function logs
  - Settlement processing completed

### Settlement Reconcile

- **Schedule:** Every 6 hours
- **Next Run:** Calculate next 6-hour interval
- **What to Check:**
  - quick-handler Edge Function logs
  - Reconciliation completed

## Troubleshooting

### Cron Job Not Running

1. **Check if job is active:**
   ```sql
   SELECT active FROM cron.job WHERE jobname = 'weekly-close-staging';
   ```
   Should return `true`

2. **Check cron job history:**
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'weekly-close-staging')
   ORDER BY start_time DESC 
   LIMIT 5;
   ```

3. **Check for errors in return_message**

### Edge Function Not Called

1. **Verify function exists:**
   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'call_weekly_close';
   ```

2. **Test function manually:**
   ```sql
   SELECT public.call_weekly_close();
   ```

3. **Check Edge Function logs for errors**

### Service Role Key Issues

1. **Verify key is set:**
   ```sql
   SELECT COUNT(*) FROM public._internal_config WHERE key = 'service_role_key';
   ```
   Should return `1`

2. **Check key value:**
   ```sql
   SELECT LEFT(value, 20) || '...' FROM public._internal_config WHERE key = 'service_role_key';
   ```

3. **Test function (will fail if key missing):**
   ```sql
   SELECT public.call_weekly_close();
   ```

## Quick Verification Checklist

- [ ] Cron jobs visible in Dashboard (3 jobs in each environment)
- [ ] All cron jobs show as "Active"
- [ ] Edge Function logs show recent test invocations
- [ ] `call_weekly_close()` function executes without errors
- [ ] Service role key is set in `_internal_config` table
- [ ] No duplicate cron jobs
- [ ] Next scheduled runs are correct

## Automated Verification

Run the verification script:

```bash
./scripts/verify_phase6.sh both
```

This will:
- Test `call_weekly_close()` function
- Verify cron jobs exist
- Check all components are working

## Next Steps

After verification:
1. ✅ Monitor first scheduled run (next Monday at 17:00 UTC)
2. ✅ Set up alerts/notifications for failures (optional)
3. ✅ Document any issues or adjustments needed


