-- ==============================================================================
-- Cleanup Old Reconciliation Cron Job
-- ==============================================================================
-- Optional: Remove the old settlement-reconcile cron job (jobid 3)
-- The new process_reconciliation_queue() function is better because it:
-- - Verifies refunds before marking complete
-- - Handles retries properly
-- - Uses app_config for configuration
-- ==============================================================================

-- Unschedule the old job (optional - you can keep it if you want)
SELECT cron.unschedule(3);

-- Verify it was removed
SELECT jobid, jobname, schedule, active, command
FROM cron.job 
WHERE jobid = 3;

-- Should return no rows if successfully removed

