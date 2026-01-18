-- ==============================================================================
-- Simple Cron Job Check (Quick Version)
-- ==============================================================================
-- Run this for a quick overview of cron job status
-- ==============================================================================

-- Quick check: Are the jobs running?
SELECT 
  j.jobname,
  j.active,
  COUNT(jrd.runid) AS runs_last_hour,
  MAX(jrd.start_time) AS last_run,
  MAX(jrd.status) AS last_status,
  CASE 
    WHEN j.active = false THEN '❌ Job is INACTIVE'
    WHEN MAX(jrd.start_time) > NOW() - INTERVAL '2 minutes' THEN '✅ Running recently'
    WHEN MAX(jrd.start_time) IS NULL THEN '❌ Never executed'
    ELSE '⚠️ Last run: ' || ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(jrd.start_time)))::numeric / 60, 1) || ' minutes ago'
  END AS status
FROM cron.job j
LEFT JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
  AND jrd.start_time > NOW() - INTERVAL '1 hour'
WHERE j.jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
GROUP BY j.jobid, j.jobname, j.active
ORDER BY j.jobname;

