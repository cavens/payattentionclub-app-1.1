-- ==============================================================================
-- Setup Cron Job for Weekly Close - STAGING
-- ==============================================================================
-- Run this in: Staging Supabase Project → SQL Editor
-- ==============================================================================

-- Step 1: Enable pg_cron extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Step 2: Remove existing job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-staging';

-- Step 3: Schedule new cron job
-- Schedule: Every Monday at 17:00 UTC (12:00 PM EST / 1:00 PM EDT)
-- Cron format: minute hour day-of-month month day-of-week
SELECT cron.schedule(
    'weekly-close-staging',           -- Job name
    '0 17 * * 1',                     -- Schedule: Every Monday at 17:00 UTC
    $$SELECT public.call_weekly_close();$$  -- Call the function
);

-- Step 4: Verify the job was created
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active,
    nodename,
    nodeport
FROM cron.job
WHERE jobname = 'weekly-close-staging';

-- ==============================================================================
-- IMPORTANT: Before running this, ensure:
-- 1. pg_cron extension is enabled (Database → Extensions)
-- 2. app.settings.service_role_key is set (Database → Settings → Custom Postgres Config)
--    Value: Your STAGING_SUPABASE_SERVICE_ROLE_KEY from .env
-- ==============================================================================


