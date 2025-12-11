# Phase 6: Cron Jobs Setup Guide

## Overview

This guide sets up automated cron jobs to run the `weekly-close` Edge Function every Monday at 12:00 PM EST (17:00 UTC).

## Prerequisites

- ✅ `call_weekly_close()` function deployed in both environments
- ✅ `pg_cron` extension available in Supabase
- ✅ Service role key available

## Step 1: Enable pg_cron Extension

### Staging

1. Go to [Supabase Dashboard → Staging Project](https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl)
2. Navigate to **Database → Extensions**
3. Search for `pg_cron`
4. Click **Enable** if not already enabled

### Production

1. Go to [Supabase Dashboard → Production Project](https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj)
2. Navigate to **Database → Extensions**
3. Search for `pg_cron`
4. Click **Enable** if not already enabled

## Step 2: Set Service Role Key

The `call_weekly_close()` function requires `app.settings.service_role_key` to be set in the database.

### Option A: Via SQL Editor (if you have superuser access)

**Staging:**
```sql
ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_STAGING_SERVICE_ROLE_KEY';
```

**Production:**
```sql
ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_PRODUCTION_SERVICE_ROLE_KEY';
```

### Option B: Via Supabase Dashboard (Recommended)

1. Go to **Database → Settings → Database Settings**
2. Scroll to **Custom Postgres Config**
3. Add new config:
   - **Key:** `app.settings.service_role_key`
   - **Value:** Your service role key (from `.env` file)
4. Click **Save**

**Staging Service Role Key:** `STAGING_SUPABASE_SERVICE_ROLE_KEY` from `.env`  
**Production Service Role Key:** `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY` from `.env`

## Step 3: Schedule Cron Job

### Staging

1. Go to **Staging Project → SQL Editor**
2. Run the following SQL:

```sql
-- Remove existing job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-staging';

-- Schedule new job: Every Monday at 17:00 UTC (12:00 PM EST)
SELECT cron.schedule(
    'weekly-close-staging',           -- Job name
    '0 17 * * 1',                     -- Schedule: Every Monday at 17:00 UTC
    $$SELECT public.call_weekly_close();$$
);

-- Verify the job was created
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active
FROM cron.job
WHERE jobname = 'weekly-close-staging';
```

### Production

1. Go to **Production Project → SQL Editor**
2. Run the following SQL:

```sql
-- Remove existing job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-production';

-- Schedule new job: Every Monday at 17:00 UTC (12:00 PM EST)
SELECT cron.schedule(
    'weekly-close-production',        -- Job name
    '0 17 * * 1',                     -- Schedule: Every Monday at 17:00 UTC
    $$SELECT public.call_weekly_close();$$
);

-- Verify the job was created
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active
FROM cron.job
WHERE jobname = 'weekly-close-production';
```

## Step 4: Verify Setup

### Check Cron Jobs

Run this SQL in each environment:

```sql
-- Check all cron jobs
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active,
    nodename,
    nodeport
FROM cron.job
WHERE jobname LIKE 'weekly-close%';
```

### Check Service Role Key

```sql
-- Check if service_role_key is set
SELECT 
    CASE 
        WHEN current_setting('app.settings.service_role_key', true) IS NOT NULL 
        THEN '✅ Set'
        ELSE '❌ Not set'
    END AS status;
```

### Test Manually

Test the function manually before waiting for the cron job:

```sql
-- Test the function
SELECT public.call_weekly_close();
```

Then check the Edge Function logs to verify it was called:
- **Staging:** [Functions → weekly-close → Logs](https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs)
- **Production:** [Functions → weekly-close → Logs](https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs)

## Schedule Details

- **Cron Expression:** `0 17 * * 1`
- **Meaning:** Every Monday at 17:00 UTC
- **EST Equivalent:** 12:00 PM EST (1:00 PM EDT during daylight saving)
- **Frequency:** Weekly

## Troubleshooting

### Cron Job Not Running

1. **Check if pg_cron is enabled:**
   ```sql
   SELECT * FROM pg_extension WHERE extname = 'pg_cron';
   ```

2. **Check if job is active:**
   ```sql
   SELECT active FROM cron.job WHERE jobname = 'weekly-close-staging';
   ```

3. **Check cron job history:**
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'weekly-close-staging')
   ORDER BY start_time DESC 
   LIMIT 10;
   ```

### Service Role Key Not Set

If you get an error: `service_role_key not set`

1. Verify it's set in database settings
2. Try setting it via SQL (if you have permissions):
   ```sql
   ALTER DATABASE postgres SET app.settings.service_role_key = 'your-key-here';
   ```

### Function Not Found

If you get an error: `function call_weekly_close() does not exist`

1. Verify the function exists:
   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'call_weekly_close';
   ```

2. If missing, deploy it from `supabase/remote_rpcs/call_weekly_close.sql`

## Automated Setup (Alternative)

If you have `psql` installed, you can use the automated script:

```bash
# Setup for staging
./scripts/setup_cron_jobs.sh staging

# Setup for production
./scripts/setup_cron_jobs.sh production

# Setup for both
./scripts/setup_cron_jobs.sh both
```

## Verification Checklist

- [ ] pg_cron extension enabled in staging
- [ ] pg_cron extension enabled in production
- [ ] Service role key set in staging database
- [ ] Service role key set in production database
- [ ] Cron job scheduled in staging
- [ ] Cron job scheduled in production
- [ ] Manual test successful in staging
- [ ] Manual test successful in production

## Next Steps

After setup:
1. Monitor the first scheduled run (next Monday at 17:00 UTC)
2. Check Edge Function logs to verify execution
3. Verify that penalties were calculated and charged correctly
4. Set up alerts/notifications for cron job failures (optional)

