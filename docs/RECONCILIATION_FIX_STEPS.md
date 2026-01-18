# Reconciliation Queue Fix - Step-by-Step Guide

**Date**: 2026-01-18  
**Status**: 🔧 **IN PROGRESS**

---

## Problem Summary

- Queue entry stuck in `processing` status
- Cron job doesn't exist (Step 6 returned no rows)
- `quick-handler` Edge Function not being called
- Need to add authentication similar to `bright-service`

---

## ✅ What's Been Done

1. ✅ **Updated `quick-handler` Edge Function** - Added `RECONCILIATION_SECRET` authentication (like `bright-service`)
2. ✅ **Updated `process_reconciliation_queue.sql`** - Now uses `x-reconciliation-secret` header from `app_config`
3. ✅ **Created helper scripts** - For setting up secrets and cron jobs

---

## 📋 Steps to Complete

### Step 1: Reset Stuck Queue Entry

Run this SQL in Supabase SQL Editor:

```sql
UPDATE reconciliation_queue
SET status = 'pending', 
    processed_at = NULL,
    error_message = NULL
WHERE id = '5f6bc284-c57d-4c5e-9204-1d42c8ff694e';
```

**Or use the prepared script**:
- File: `supabase/sql-drafts/reset_queue_entry.sql`

---

### Step 2: Check `quick-handler` Visibility

**In Supabase Dashboard**:
1. Go to **Edge Functions** → **quick-handler**
2. Click **Settings**
3. Check **Visibility**: Should be **Public** (for secret header auth to work)

**Or run this SQL**:
- File: `supabase/sql-drafts/check_quick_handler_status.sql`

---

### Step 3: Set RECONCILIATION_SECRET in Edge Function Secrets

**In Supabase Dashboard**:
1. Go to **Edge Functions** → **quick-handler** → **Settings** → **Secrets**
2. Add new secret:
   - **Key**: `RECONCILIATION_SECRET`
   - **Value**: (use a secure random string, e.g., generate with `openssl rand -hex 32`)

**Note**: Save this value - you'll need it for Step 4!

---

### Step 4: Set RECONCILIATION_SECRET in app_config

**Option A: Using the script** (recommended):

1. Add to your `.env` file:
   ```bash
   RECONCILIATION_SECRET=your-secret-value-here
   ```

2. Run the script:
   ```bash
   deno run --allow-net --allow-env --allow-read scripts/set_reconciliation_secret_in_app_config.ts
   ```

**Option B: Manual SQL**:

```sql
INSERT INTO public.app_config (key, value, description) 
VALUES (
  'reconciliation_secret', 
  'your-secret-value-here',  -- Must match Step 3 value!
  'Secret for authenticating reconciliation cron job calls to quick-handler Edge Function'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

**File**: `scripts/set_reconciliation_secret_in_app_config.ts`

---

### Step 5: Deploy Updated `quick-handler` Function

The function code has been updated to check for `RECONCILIATION_SECRET`. Deploy it:

```bash
cd payattentionclub-app-1.1
supabase functions deploy quick-handler --project-ref <your-project-ref>
```

**Or use the deploy script**:
```bash
./scripts/deploy.sh staging
```

---

### Step 6: Apply Updated `process_reconciliation_queue` Function

The SQL function has been updated. Apply it:

**Option A: Via Supabase Dashboard**:
1. Go to **SQL Editor**
2. Copy contents of `supabase/remote_rpcs/process_reconciliation_queue.sql`
3. Paste and execute

**Option B: Via deploy script** (if it supports RPC functions):
```bash
./scripts/deploy.sh staging
```

---

### Step 7: Create Cron Jobs

**Run this SQL in Supabase SQL Editor**:

```sql
-- File: supabase/sql-drafts/setup_reconciliation_cron.sql
-- Or use the migration: supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql
```

**Or run the prepared script**:
- File: `supabase/sql-drafts/setup_reconciliation_cron.sql`

**Verify cron jobs were created**:
```sql
SELECT jobid, jobname, schedule, active, command
FROM cron.job 
WHERE jobname LIKE '%reconciliation%'
ORDER BY jobname;
```

**Expected results**:
- `process-reconciliation-queue-testing`: schedule = `* * * * *` (every minute), active = true
- `process-reconciliation-queue-normal`: schedule = `*/10 * * * *` (every 10 minutes), active = true

---

## ✅ Verification Steps

### 1. Check Queue Entry Status

```sql
SELECT id, user_id, week_start_date, status, processed_at, retry_count, error_message
FROM reconciliation_queue
ORDER BY created_at DESC
LIMIT 5;
```

**Expected**: Entry should be `pending` (after Step 1)

---

### 2. Check Cron Job Execution

Wait 1-2 minutes, then check:

```sql
SELECT 
  jobid,
  runid,
  status,
  return_message,
  start_time,
  end_time
FROM cron.job_run_details
WHERE jobid IN (
  SELECT jobid FROM cron.job 
  WHERE jobname LIKE '%reconciliation%'
)
ORDER BY start_time DESC
LIMIT 5;
```

**Expected**: Recent entries with `status = 'succeeded'`

---

### 3. Check Queue Entry After Processing

```sql
SELECT id, status, processed_at, error_message
FROM reconciliation_queue
WHERE id = '5f6bc284-c57d-4c5e-9204-1d42c8ff694e';
```

**Expected**: Status should change from `pending` → `processing` → `completed`

---

### 4. Check Refund Was Issued

```sql
SELECT 
  user_id,
  week_start_date,
  refund_amount_cents,
  needs_reconciliation,
  reconciliation_reason
FROM user_week_penalties
WHERE user_id = '9edd63d4-84ce-47f2-8b60-eda484d28a12'
  AND week_start_date = '2026-01-17';
```

**Expected**: `refund_amount_cents > 0`, `needs_reconciliation = false`

---

### 5. Check `quick-handler` Logs

**In Supabase Dashboard**:
1. Go to **Edge Functions** → **quick-handler** → **Logs**
2. Look for recent entries with:
   - `"quick-handler: Authorized via reconciliation secret"`
   - `"settlement-reconcile invoked"`

**Expected**: Recent log entries showing the function was called

---

## 🔍 Troubleshooting

### Issue: Queue entry stays in `processing`

**Possible causes**:
1. Cron job not running - check Step 7
2. `quick-handler` not receiving requests - check Step 2 (visibility) and Step 3 (secret)
3. Secret mismatch - verify Step 3 and Step 4 use the same value

**Debug**:
```sql
-- Check if cron job exists and is active
SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname LIKE '%reconciliation%';

-- Check recent cron executions
SELECT * FROM cron.job_run_details 
WHERE jobid IN (SELECT jobid FROM cron.job WHERE jobname LIKE '%reconciliation%')
ORDER BY start_time DESC LIMIT 5;

-- Check app_config has the secret
SELECT key, CASE WHEN key = 'reconciliation_secret' THEN '***SET***' ELSE value END AS value
FROM app_config WHERE key = 'reconciliation_secret';
```

---

### Issue: `quick-handler` returns 401 Unauthorized

**Possible causes**:
1. `RECONCILIATION_SECRET` not set in Edge Function secrets (Step 3)
2. Secret mismatch between Edge Function and `app_config` (Step 3 vs Step 4)
3. Function is Private but secret header not being sent

**Fix**:
1. Verify Step 3 and Step 4 use the same secret value
2. Make sure function is Public (Step 2)
3. Check `process_reconciliation_queue` is using the secret header (Step 6)

---

### Issue: Cron job exists but not running

**Possible causes**:
1. `pg_cron` extension not enabled
2. Cron job is inactive

**Fix**:
```sql
-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Check if cron job is active
SELECT jobid, jobname, active FROM cron.job WHERE jobname LIKE '%reconciliation%';

-- If inactive, reactivate it (replace jobid with actual value)
SELECT cron.alter_job(jobid, active := true) FROM cron.job WHERE jobname LIKE '%reconciliation%';
```

---

## 📝 Summary

**Files Modified**:
1. ✅ `supabase/functions/quick-handler/index.ts` - Added secret authentication
2. ✅ `supabase/remote_rpcs/process_reconciliation_queue.sql` - Uses secret header from app_config

**Files Created**:
1. ✅ `scripts/set_reconciliation_secret_in_app_config.ts` - Helper script
2. ✅ `supabase/sql-drafts/setup_reconciliation_cron.sql` - Cron setup script
3. ✅ `supabase/sql-drafts/reset_queue_entry.sql` - Reset stuck entry
4. ✅ `supabase/sql-drafts/check_quick_handler_status.sql` - Status check

**Next Steps**:
1. Follow Steps 1-7 above
2. Verify using the verification steps
3. Monitor queue entry status and `quick-handler` logs

---

**End of Guide**

