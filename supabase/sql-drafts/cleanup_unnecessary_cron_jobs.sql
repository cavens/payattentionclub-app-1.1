-- ==============================================================================
-- Cleanup Unnecessary Cron Jobs
-- ==============================================================================
-- Removes old/unused cron jobs that are no longer needed:
-- 1. settlement-reconcile (jobid 3) - Replaced by process_reconciliation_queue()
-- 2. auto-settlement-checker (jobid 5) - No Edge Function exists, appears unused
-- ==============================================================================

-- 1. Remove settlement-reconcile (jobid 3)
-- This old cron job is replaced by process_reconciliation_queue() which:
-- - Verifies refunds before marking complete
-- - Handles retries properly
-- - Uses app_config for configuration
-- - Has proper authentication headers
SELECT cron.unschedule(3) AS removed_settlement_reconcile;

-- 2. Remove auto-settlement-checker (jobid 5)
-- This cron job calls an Edge Function that doesn't exist
-- Settlement is now handled by:
-- - Weekly-Settlement (normal mode, Tuesday 12:00)
-- - run-settlement-testing (testing mode, every 2 minutes)
SELECT cron.unschedule(5) AS removed_auto_settlement_checker;

-- 3. Verify the jobs were removed
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
WHERE jobid IN (3, 5)
ORDER BY jobid;

-- Should return no rows if successfully removed

-- 4. Show remaining cron jobs for verification
SELECT 
  jobid,
  jobname,
  schedule,
  active
FROM cron.job 
ORDER BY jobid;

