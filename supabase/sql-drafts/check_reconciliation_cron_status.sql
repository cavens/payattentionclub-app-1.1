-- ==============================================================================
-- Check Reconciliation Cron Job Status
-- ==============================================================================
-- Run this in Supabase SQL Editor to verify cron jobs are running
-- ==============================================================================

-- 1. Check if reconciliation cron jobs exist and are active
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  database,
  username,
  command
FROM cron.job 
WHERE jobname LIKE '%reconciliation%'
ORDER BY jobname;

-- Expected results:
-- - process-reconciliation-queue-testing: schedule = '* * * * *' (every minute), active = true
-- - process-reconciliation-queue-normal: schedule = '*/10 * * * *' (every 10 minutes), active = true

-- ==============================================================================
-- 2. Check recent cron job execution history
-- ==============================================================================
-- Note: This requires pg_cron extension to log job runs
-- If you see recent entries, the cron job is running

SELECT 
  jobid,
  runid,
  job_pid,
  database,
  username,
  command,
  status,
  return_message,
  start_time,
  end_time
FROM cron.job_run_details
WHERE jobid IN (
  SELECT jobid FROM cron.job 
  WHERE jobname LIKE '%reconciliation%'
)
ORDER BY start_time DESC
LIMIT 10;

-- ==============================================================================
-- 3. Check if process_reconciliation_queue function exists
-- ==============================================================================

SELECT 
  routine_name,
  routine_type,
  data_type AS return_type
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name = 'process_reconciliation_queue';

-- Expected: 1 row with routine_name = 'process_reconciliation_queue'

-- ==============================================================================
-- 4. Manually trigger reconciliation queue processing (for testing)
-- ==============================================================================
-- Uncomment the line below to manually trigger the queue processor:
-- SELECT public.process_reconciliation_queue();

-- ==============================================================================
-- 5. Check reconciliation queue entries for a specific user/week
-- ==============================================================================

SELECT 
  id,
  user_id,
  week_start_date,
  reconciliation_delta_cents,
  status,
  created_at,
  processed_at,
  error_message,
  retry_count
FROM public.reconciliation_queue
WHERE user_id = 'bf800520-094c-4a20-96f0-1afe99d0c05d'
  AND week_start_date = '2026-01-17'
ORDER BY created_at DESC;

-- ==============================================================================
-- 6. Check penalty record reconciliation status
-- ==============================================================================

SELECT 
  user_id,
  week_start_date,
  settlement_status,
  needs_reconciliation,
  reconciliation_delta_cents,
  charged_amount_cents,
  actual_amount_cents,
  refund_amount_cents,
  refund_payment_intent_id,
  refund_issued_at,
  last_updated
FROM public.user_week_penalties
WHERE user_id = 'bf800520-094c-4a20-96f0-1afe99d0c05d'
  AND week_start_date = '2026-01-17';


