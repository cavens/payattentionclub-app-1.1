-- ==============================================================================
-- Verify Reconciliation Cron Jobs Exist
-- ==============================================================================
-- Run this to check if the cron jobs already exist
-- ==============================================================================

-- Check ALL cron jobs (to see what's actually there)
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
ORDER BY jobname;

-- Specifically check for reconciliation cron jobs
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
WHERE jobname LIKE '%reconciliation%'
   OR jobname LIKE '%reconcile%'
ORDER BY jobname;

-- If no rows returned, the cron jobs don't exist and need to be created
-- If rows are returned, check if they're active and have the correct schedule

