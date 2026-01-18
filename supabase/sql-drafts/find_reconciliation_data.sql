-- ==============================================================================
-- Find Reconciliation Data (Check if rows exist)
-- ==============================================================================

-- Check if penalty record exists
SELECT 
  'Penalty Record Exists?' AS check_type,
  COUNT(*) AS count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found'
    ELSE '❌ Not found'
  END AS result
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- Check if queue entry exists
SELECT 
  'Queue Entry Exists?' AS check_type,
  COUNT(*) AS count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found'
    ELSE '❌ Not found'
  END AS result
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- If penalty record exists, show it
SELECT 
  'Penalty Record' AS check_type,
  user_id,
  week_start_date,
  needs_reconciliation,
  reconciliation_delta_cents,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents,
  settlement_status
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- If queue entry exists, show it
SELECT 
  'Queue Entry' AS check_type,
  id,
  user_id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at,
  created_at
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC;

-- Show all penalty records for this user (to see what weeks exist)
SELECT 
  'All Penalty Records for User' AS check_type,
  user_id,
  week_start_date,
  needs_reconciliation,
  refund_amount_cents,
  settlement_status
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
ORDER BY week_start_date DESC
LIMIT 5;

