-- ==============================================================================
-- Quick Check: Reconciliation Status
-- ==============================================================================

-- 1. Queue entry status
SELECT 
  'Queue Entry' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at,
  CASE 
    WHEN status = 'completed' THEN '✅ Completed'
    WHEN status = 'processing' THEN '🔄 Processing (check if stuck)'
    WHEN status = 'pending' THEN '⏳ Pending (should be processed)'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown')
    ELSE '❓ ' || status
  END AS result
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC
LIMIT 1;

-- 2. Recent quick-handler responses
SELECT 
  'Recent Responses' AS check_type,
  id,
  status_code,
  LEFT(content, 300) AS content_preview,
  CASE 
    WHEN status_code = 200 AND content LIKE '%refundsIssued%' THEN '✅ Success - Refund issued'
    WHEN status_code = 200 AND content LIKE '%processed%' THEN '✅ Success - Processed'
    WHEN status_code = 200 AND content LIKE '%stripe is not defined%' THEN '❌ Stripe not initialized'
    WHEN status_code = 200 AND content LIKE '%Stripe credentials missing%' THEN '❌ Missing Stripe secret'
    WHEN status_code = 401 THEN '❌ Authentication error'
    WHEN status_code >= 400 THEN '❌ Error: ' || status_code
    WHEN status_code IS NULL THEN '⏳ Pending'
    ELSE '❓ Status: ' || COALESCE(status_code::text, 'NULL')
  END AS result
FROM net._http_response
WHERE content LIKE '%refundsIssued%' 
   OR content LIKE '%chargesIssued%'
   OR content LIKE '%stripe is not defined%'
   OR content LIKE '%Stripe credentials missing%'
   OR content LIKE '%processed%'
ORDER BY id DESC
LIMIT 5;

-- 3. Reconciliation status
SELECT 
  'Reconciliation Status' AS check_type,
  needs_reconciliation,
  reconciliation_delta_cents,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents,
  CASE 
    WHEN needs_reconciliation = false AND refund_amount_cents > 0 THEN '✅ Refund issued: ' || refund_amount_cents || ' cents'
    WHEN needs_reconciliation = false THEN '✅ Reconciliation complete'
    WHEN needs_reconciliation = true AND reconciliation_delta_cents < 0 THEN '⏳ Needs refund: ' || ABS(reconciliation_delta_cents) || ' cents'
    WHEN needs_reconciliation = true AND reconciliation_delta_cents > 0 THEN '⏳ Needs charge: ' || reconciliation_delta_cents || ' cents'
    ELSE '❓ Status unclear'
  END AS result
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

