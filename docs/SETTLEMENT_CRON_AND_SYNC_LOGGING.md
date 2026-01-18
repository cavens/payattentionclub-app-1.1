# Settlement Cron Job and Sync Logging Implementation
**Date**: 2026-01-17

---

## What Was Done

### 1. Created Settlement Cron Job Migration

**File**: `supabase/migrations/20260117180000_setup_settlement_cron_testing_mode.sql`

**What it does**:
- Creates `call_settlement()` helper function that:
  - Gets `settlement_secret` from `app_config` table
  - Gets `supabase_url` and `service_role_key` from `app_config`
  - Calls `bright-service` Edge Function with required headers:
    - `x-manual-trigger: true` (required for testing mode)
    - `x-settlement-secret: <secret>` (required for authentication)
- Sets up cron job `run-settlement-testing` that:
  - Runs every 2 minutes (`*/2 * * * *`)
  - Calls `call_settlement()` function

**Requirements**:
- `settlement_secret` must be set in `app_config` table
- `supabase_url` must be set in `app_config` table
- `service_role_key` must be set in `app_config` table

**To apply**:
```bash
# Apply the migration via Supabase Dashboard SQL Editor or CLI
supabase db push
```

**To set settlement_secret in app_config**:
```sql
INSERT INTO public.app_config (key, value) 
VALUES ('settlement_secret', 'your-secret-here')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

---

### 2. Added Detailed Logging to Usage Sync

**File**: `payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/UsageSyncManager.swift`

**What was added**:

#### A. `updateAndSync()` function:
- Logs when function is called
- Logs each step (update entries, sync to backend)
- Logs success/failure with detailed error information

#### B. `syncToBackend()` function:
- Logs when sync starts
- Logs sync coordinator approval/rejection
- Logs number of unsynced entries found
- Logs details of each entry to be synced (date, minutes, week start date)
- Logs authentication status
- Logs sync progress (starting, completed, dates synced)
- Logs detailed error information on failure

#### C. `getUnsyncedUsage()` function:
- Logs when function is called
- Logs total keys found in App Group
- Logs keys after filtering
- Logs number of daily_usage_* keys found
- Logs each entry found (synced/unsynced status)
- Logs summary (total, synced, unsynced, failed)
- Logs date range of unsynced entries

**Log format**:
All logs use `NSLog()` with prefix `SYNC UsageSyncManager:` and emoji indicators:
- 🔄 = Process started
- ✅ = Success
- ❌ = Error
- ⚠️ = Warning
- 📊 = Statistics/Summary
- 📝 = Entry details
- 🔍 = Searching/Scanning
- 🔐 = Authentication
- 🚀 = Starting operation
- 📤 = Upload/Send
- 🏷️ = Marking/Updating
- 🏁 = Completed
- ⏭️ = Skipped

---

## How to Use

### Settlement Cron Job

1. **Set settlement_secret in app_config**:
   ```sql
   INSERT INTO public.app_config (key, value) 
   VALUES ('settlement_secret', 'your-secret-here')
   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
   ```

2. **Apply the migration**:
   - Via Supabase Dashboard SQL Editor, or
   - Via CLI: `supabase db push`

3. **Verify cron job is scheduled**:
   ```sql
   SELECT * FROM cron.job WHERE jobname = 'run-settlement-testing';
   ```

4. **Test the function manually**:
   ```sql
   SELECT public.call_settlement();
   ```

5. **Check cron job logs**:
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'run-settlement-testing')
   ORDER BY start_time DESC 
   LIMIT 10;
   ```

### Usage Sync Logging

1. **Open Xcode console** when testing the app

2. **Look for logs** with prefix `SYNC UsageSyncManager:`

3. **Key logs to watch for**:
   - `🔄 updateAndSync() called` - Sync triggered
   - `📊 Found X unsynced entry/entries` - Entries found
   - `🔐 Authentication status: ✅ Authenticated` - Auth check
   - `🚀 Starting sync of X entries to backend...` - Sync started
   - `✅ Synced dates: ...` - Success
   - `❌ Failed to sync entries` - Error

4. **If sync fails**, check:
   - Authentication status log
   - Error details log
   - Number of unsynced entries found
   - Whether entries exist in App Group

---

## Troubleshooting

### Settlement Cron Job Not Running

1. **Check if cron job exists**:
   ```sql
   SELECT * FROM cron.job WHERE jobname = 'run-settlement-testing';
   ```

2. **Check if settlement_secret is set**:
   ```sql
   SELECT * FROM app_config WHERE key = 'settlement_secret';
   ```

3. **Check cron job run history**:
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'run-settlement-testing')
   ORDER BY start_time DESC 
   LIMIT 10;
   ```

4. **Test function manually**:
   ```sql
   SELECT public.call_settlement();
   ```

### Usage Sync Not Working

1. **Check logs** in Xcode console for:
   - `SYNC UsageSyncManager:` prefix
   - Authentication status
   - Number of entries found
   - Error messages

2. **Check App Group** for entries:
   - Look for `daily_usage_*` keys
   - Check if entries are marked as `synced: true`

3. **Check database** for synced entries:
   ```sql
   SELECT * FROM daily_usage 
   WHERE user_id = '<your-user-id>'
   ORDER BY date DESC;
   ```

4. **Check penalty record**:
   ```sql
   SELECT * FROM user_week_penalties 
   WHERE user_id = '<your-user-id>'
   ORDER BY week_start_date DESC;
   ```

---

## Next Steps

1. **Apply the migration** to create the settlement cron job
2. **Set settlement_secret** in app_config table
3. **Test the app** and watch Xcode console for sync logs
4. **Verify** that:
   - Settlement runs automatically every 2 minutes in testing mode
   - Usage sync logs show what's happening
   - Entries are being synced to the database

---

## Files Modified

1. ✅ `supabase/migrations/20260117180000_setup_settlement_cron_testing_mode.sql` (new)
2. ✅ `payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/UsageSyncManager.swift` (updated)


