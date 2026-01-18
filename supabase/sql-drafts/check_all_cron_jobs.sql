-- ==============================================================================
-- Check All Cron Jobs
-- ==============================================================================
-- Run this in Supabase SQL Editor to see all cron jobs
-- ==============================================================================

-- Check ALL cron jobs
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  database,
  username,
  LEFT(command, 150) as command_preview
FROM cron.job 
ORDER BY jobname;

-- Check specifically for settlement-related cron jobs
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
WHERE jobname LIKE '%settlement%'
   OR jobname LIKE '%bright%'
   OR command LIKE '%call_settlement%'
   OR command LIKE '%bright-service%'
ORDER BY jobname;

-- Check for reconciliation cron jobs
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

