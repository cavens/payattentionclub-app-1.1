-- ==============================================================================
-- Check Reconciliation Queue Entry for Test
-- ==============================================================================
-- Run this to see if a queue entry was created for the test commitment
-- ==============================================================================

-- Check for queue entry for this user/week
SELECT 
  id,
  user_id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  created_at,
  processed_at
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC;

-- If no entry found, check if reconciliation should have been triggered
SELECT 
  user_id,
  week_start_date,
  needs_reconciliation,
  reconciliation_delta_cents,
  reconciliation_reason,
  reconciliation_detected_at,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

