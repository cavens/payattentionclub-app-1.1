-- ==============================================================================
-- Comprehensive Reconciliation Diagnosis
-- ==============================================================================
-- Run this to diagnose why reconciliation isn't working
-- ==============================================================================

-- 1. Check if queue entry exists
SELECT 
  'Queue Entry Status' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  created_at,
  processed_at,
  CASE 
    WHEN status = 'pending' THEN '⏳ Waiting for cron job'
    WHEN status = 'processing' THEN '🔄 Being processed (check processed_at timestamp)'
    WHEN status = 'completed' THEN '✅ Should be done (but refund not showing?)'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown error')
    ELSE '❓ Unknown status'
  END AS status_meaning
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC;

-- 2. Check penalty record details
SELECT 
  'Penalty Record' AS check_type,
  needs_reconciliation,
  reconciliation_delta_cents,
  reconciliation_reason,
  reconciliation_detected_at,
  refund_amount_cents,
  refund_payment_intent_id,
  refund_issued_at,
  charged_amount_cents,
  actual_amount_cents,
  settlement_status,
  last_updated
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- 3. Check recent cron job executions
SELECT 
  'Cron Job Execution' AS check_type,
  jobid,
  runid,
  status,
  return_message,
  start_time,
  end_time,
  CASE 
    WHEN status = 'succeeded' THEN '✅ Ran successfully'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(return_message, 'Unknown error')
    ELSE '❓ Status: ' || status
  END AS execution_status
FROM cron.job_run_details
WHERE jobid IN (
  SELECT jobid FROM cron.job 
  WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
)
ORDER BY start_time DESC
LIMIT 5;

-- 4. Check if reconciliation_secret is set in app_config
SELECT 
  'App Config' AS check_type,
  key,
  CASE WHEN key = 'reconciliation_secret' THEN '***SET***' ELSE value END AS value,
  'Required for process_reconciliation_queue to authenticate with quick-handler' AS note
FROM app_config
WHERE key IN ('reconciliation_secret', 'service_role_key', 'supabase_url', 'testing_mode')
ORDER BY key;

