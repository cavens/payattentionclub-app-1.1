-- ==============================================================================
-- Check ALL Cron Jobs
-- ==============================================================================
-- Shows all cron jobs with full details - no filtering
-- ==============================================================================

SELECT 
  jobid,
  jobname,
  schedule,
  active,
  database,
  username,
  nodename,
  nodeport,
  command
FROM cron.job 
ORDER BY jobid;

