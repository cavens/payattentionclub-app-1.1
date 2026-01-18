-- Verify Reconciliation Queue Cron Jobs
-- Run this query after applying the cron setup migration

-- Check if both cron jobs exist
SELECT 
  jobid,
  jobname,
  schedule,
  command,
  nodename,
  nodeport,
  database,
  username,
  active,
  jobid
FROM cron.job 
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
ORDER BY jobname;

-- Expected result: 2 rows
-- - process-reconciliation-queue-testing: schedule = '* * * * *' (every minute)
-- - process-reconciliation-queue-normal: schedule = '*/10 * * * *' (every 10 minutes)


