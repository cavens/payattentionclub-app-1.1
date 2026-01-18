-- ==============================================================================
-- Quick Check: Queue Entry and Cron Status
-- ==============================================================================

-- 1. Check if queue entry exists for this user/week
SELECT 
  'Queue Entry' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  created_at,
  processed_at,
  CASE 
    WHEN status = 'pending' THEN '⏳ Waiting for cron job (should process within 1 min)'
    WHEN status = 'processing' THEN '🔄 Being processed (check if processed_at is recent)'
    WHEN status = 'completed' THEN '✅ Marked complete (but refund not showing - check quick-handler logs)'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown error')
    ELSE '❓ Unknown status'
  END AS status_meaning
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC;

-- 2. Check recent cron job executions (last 5 runs)
SELECT 
  'Cron Execution' AS check_type,
  j.jobname,
  jrd.status,
  jrd.return_message,
  jrd.start_time,
  jrd.end_time,
  CASE 
    WHEN jrd.status = 'succeeded' THEN '✅ Ran successfully'
    WHEN jrd.status = 'failed' THEN '❌ Failed: ' || COALESCE(jrd.return_message, 'Unknown error')
    WHEN jrd.status IS NULL THEN '⏳ Not run yet'
    ELSE '❓ Status: ' || jrd.status
  END AS execution_status
FROM cron.job j
LEFT JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
WHERE j.jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
ORDER BY jrd.start_time DESC NULLS LAST
LIMIT 5;

-- 3. If no queue entry exists, that's the problem!
-- The rpc_sync_daily_usage should have created one when needs_reconciliation became true

