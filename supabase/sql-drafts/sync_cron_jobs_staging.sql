-- ==============================================================================
-- Sync Cron Jobs to Staging (Match Production)
-- ==============================================================================
-- Adds the missing cron jobs from production to staging
-- Run this in Staging SQL Editor
-- ==============================================================================

-- 1. Weekly Settlement (calls bright-service)
-- Runs every Tuesday at 12:00 UTC
SELECT cron.schedule(
    'Weekly-Settlement',
    '0 12 * * 2',  -- Every Tuesday at 12:00 UTC
    $$SELECT net.http_post(
        url := 'https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/bright-service',
        headers := jsonb_build_object(),
        timeout_milliseconds := 1000
    );$$
);

-- 2. Settlement Reconcile (calls quick-handler)
-- Runs every 6 hours
SELECT cron.schedule(
    'settlement-reconcile',
    '0 */6 * * *',  -- Every 6 hours
    $$SELECT net.http_post(
        url := 'https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/quick-handler',
        headers := jsonb_build_object(),
        timeout_milliseconds := 1000
    );$$
);

-- Verify all jobs
SELECT 
    jobid,
    jobname,
    schedule,
    active
FROM cron.job
ORDER BY jobid;

