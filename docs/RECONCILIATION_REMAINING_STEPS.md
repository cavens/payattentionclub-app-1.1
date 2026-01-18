# Reconciliation Setup - Remaining Steps

**Date**: 2026-01-18  
**Status**: ✅ Cron jobs exist and are active!

---

## ✅ What's Already Done

1. ✅ Queue entry reset to `pending`
2. ✅ Cron jobs exist and are active:
   - `process-reconciliation-queue-testing` (runs every minute)
   - `process-reconciliation-queue-normal` (runs every 10 minutes)
3. ✅ `process_reconciliation_queue` function updated (uses secret header)
4. ✅ `quick-handler` function code updated (checks for secret)

---

## 📋 Remaining Steps

### Step 1: Set RECONCILIATION_SECRET in Edge Function Secrets

**In Supabase Dashboard**:
1. Go to **Edge Functions** → **quick-handler** → **Settings** → **Secrets**
2. Click **Add Secret**
3. Add:
   - **Key**: `RECONCILIATION_SECRET`
   - **Value**: Generate a secure random string (e.g., `openssl rand -hex 32`)

**Save this value** - you'll need it for Step 2!

---

### Step 2: Set reconciliation_secret in app_config

**Option A: Using SQL** (quickest):

```sql
INSERT INTO public.app_config (key, value, description) 
VALUES (
  'reconciliation_secret', 
  'your-secret-value-here',  -- ⚠️ Must match Step 1 value exactly!
  'Secret for authenticating reconciliation cron job calls to quick-handler Edge Function'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

**Option B: Using the script**:

1. Add to your `.env` file:
   ```bash
   RECONCILIATION_SECRET=your-secret-value-here
   ```

2. Run:
   ```bash
   deno run --allow-net --allow-env --allow-read scripts/set_reconciliation_secret_in_app_config.ts
   ```

---

### Step 3: Deploy Updated quick-handler Function

The function code has been updated to check for `RECONCILIATION_SECRET`. Deploy it:

```bash
cd payattentionclub-app-1.1
supabase functions deploy quick-handler --project-ref auqujbppoytkeqdsgrbl
```

**Or use your deploy script**:
```bash
./scripts/deploy.sh staging
```

---

### Step 4: Verify Everything Works

Wait 1-2 minutes for the cron job to run, then check:

**A. Check queue entry status**:
```sql
SELECT id, status, processed_at, error_message
FROM reconciliation_queue
WHERE id = '5f6bc284-c57d-4c5e-9204-1d42c8ff694e';
```

**Expected**: Status should change from `pending` → `processing` → `completed`

**B. Check refund was issued**:
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

**C. Check quick-handler logs**:
- Supabase Dashboard → Edge Functions → quick-handler → Logs
- Look for: `"quick-handler: Authorized via reconciliation secret"`

---

## 🔍 Troubleshooting

### If queue entry stays in `processing`:

1. **Check cron job ran**:
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid IN (18, 19)
   ORDER BY start_time DESC LIMIT 5;
   ```

2. **Check app_config has the secret**:
   ```sql
   SELECT key, CASE WHEN key = 'reconciliation_secret' THEN '***SET***' ELSE value END AS value
   FROM app_config WHERE key = 'reconciliation_secret';
   ```

3. **Check quick-handler logs for errors**:
   - Look for 401 Unauthorized (secret mismatch)
   - Look for 500 errors (function code issues)

### If quick-handler returns 401:

- Verify `RECONCILIATION_SECRET` in Edge Function secrets matches `reconciliation_secret` in `app_config`
- Make sure you deployed the updated function (Step 3)

---

## 📝 Summary

**What you need to do**:
1. ✅ Set `RECONCILIATION_SECRET` in Edge Function secrets
2. ✅ Set `reconciliation_secret` in `app_config` (same value as Step 1)
3. ✅ Deploy updated `quick-handler` function
4. ✅ Wait and verify it works

**Files ready**:
- ✅ `supabase/functions/quick-handler/index.ts` - Updated with secret check
- ✅ `supabase/remote_rpcs/process_reconciliation_queue.sql` - Updated to use secret header
- ✅ Cron jobs exist and are active

**Optional cleanup**:
- Remove old `settlement-reconcile` cron job (jobid 3) - see `supabase/sql-drafts/cleanup_old_reconciliation_cron.sql`

---

**End of Guide**

