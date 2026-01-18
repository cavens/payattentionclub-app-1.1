-- ==============================================================================
-- Check Reconciliation Status for User
-- ==============================================================================

-- Check queue entry
SELECT 
  'Queue Entry' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at,
  created_at
FROM reconciliation_queue
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC
LIMIT 1;

-- Check penalty record
SELECT 
  'Penalty Record' AS check_type,
  needs_reconciliation,
  reconciliation_delta_cents,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents,
  settlement_status
FROM user_week_penalties
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18';

-- Check recent quick-handler responses
SELECT 
  'Recent Response' AS check_type,
  id,
  status_code,
  LEFT(content, 300) AS content_preview
FROM net._http_response
WHERE content LIKE '%14a914ef-e323-4e0e-8701-8e008422f927%'
   OR content LIKE '%refundsIssued%'
ORDER BY id DESC
LIMIT 3;

