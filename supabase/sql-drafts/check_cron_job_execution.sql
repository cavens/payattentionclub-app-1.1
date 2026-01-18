-- ==============================================================================
-- Check Cron Job Execution Status
-- ==============================================================================
-- This shows if the reconciliation queue cron jobs are running and if they're successful
-- ==============================================================================

-- 1. Check if cron jobs exist and are active
SELECT 
  'Cron Job Status' AS check_type,
  jobid,
  jobname,
  schedule,
  active,
  command,
  CASE 
    WHEN active = true THEN '✅ Active - should be running'
    WHEN active = false THEN '❌ Inactive - not running!'
    ELSE '❓ Unknown status'
  END AS status_meaning
FROM cron.job 
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
ORDER BY jobname;

-- 2. Check recent execution history (last 10 runs)
SELECT 
  'Execution History' AS check_type,
  j.jobname,
  jrd.runid,
  jrd.status,
  jrd.return_message,
  jrd.start_time,
  jrd.end_time,
  CASE 
    WHEN jrd.end_time IS NOT NULL THEN 
      EXTRACT(EPOCH FROM (jrd.end_time - jrd.start_time))::integer || ' seconds'
    ELSE 'Still running...'
  END AS duration,
  CASE 
    WHEN jrd.status = 'succeeded' THEN '✅ Succeeded'
    WHEN jrd.status = 'failed' THEN '❌ Failed: ' || COALESCE(jrd.return_message, 'Unknown error')
    WHEN jrd.status IS NULL THEN '⏳ Not executed yet'
    ELSE '❓ Status: ' || jrd.status
  END AS execution_status
FROM cron.job j
LEFT JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
WHERE j.jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
ORDER BY jrd.start_time DESC NULLS LAST
LIMIT 10;

-- 3. Check if jobs are running on schedule
-- Testing job should run every minute (* * * * *)
-- Normal job should run every 10 minutes (*/10 * * * *)
SELECT 
  'Schedule Check' AS check_type,
  j.jobname,
  j.schedule,
  COUNT(jrd.runid) AS execution_count_last_hour,
  MAX(jrd.start_time) AS last_execution,
  CASE 
    WHEN MAX(jrd.start_time) > NOW() - INTERVAL '2 minutes' THEN '✅ Running recently'
    WHEN MAX(jrd.start_time) > NOW() - INTERVAL '15 minutes' THEN '⚠️ Last run was ' || 
      EXTRACT(EPOCH FROM (NOW() - MAX(jrd.start_time)))::integer || ' seconds ago'
    WHEN MAX(jrd.start_time) IS NULL THEN '❌ Never executed'
    ELSE '❌ Last run was ' || 
      EXTRACT(EPOCH FROM (NOW() - MAX(jrd.start_time)))::integer || ' seconds ago (too long!)'
  END AS schedule_status
FROM cron.job j
LEFT JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
  AND jrd.start_time > NOW() - INTERVAL '1 hour'
WHERE j.jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
GROUP BY j.jobid, j.jobname, j.schedule
ORDER BY j.jobname;

-- 4. Check for errors in recent executions
SELECT 
  'Error Check' AS check_type,
  j.jobname,
  jrd.runid,
  jrd.status,
  jrd.return_message,
  jrd.start_time
FROM cron.job j
INNER JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
WHERE j.jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
  AND jrd.status = 'failed'
  AND jrd.start_time > NOW() - INTERVAL '1 hour'
ORDER BY jrd.start_time DESC;

