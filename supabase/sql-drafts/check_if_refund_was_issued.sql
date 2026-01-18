-- ==============================================================================
-- Check If Refund Was Actually Issued
-- ==============================================================================

-- Check penalty record
SELECT 
  'Penalty Record' AS check_type,
  refund_amount_cents,
  reconciliation_delta_cents,
  needs_reconciliation,
  settlement_status,
  CASE 
    WHEN refund_amount_cents >= ABS(reconciliation_delta_cents) THEN '✅ Refund issued: ' || refund_amount_cents || ' cents (needs: ' || ABS(reconciliation_delta_cents) || ')'
    WHEN refund_amount_cents > 0 THEN '⚠️ Partial refund: ' || refund_amount_cents || ' of ' || ABS(reconciliation_delta_cents) || ' cents'
    WHEN needs_reconciliation = false THEN '✅ Reconciliation complete (no refund needed)'
    ELSE '❌ No refund issued yet'
  END AS result
FROM user_week_penalties
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18';

-- Check payment records for refunds
SELECT 
  'Refund Payments' AS check_type,
  id,
  payment_type,
  amount_cents,
  status,
  created_at
FROM payments
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18'
  AND payment_type = 'penalty_refund'
ORDER BY created_at DESC;

-- Check most recent quick-handler responses for this user
SELECT 
  'Recent Responses' AS check_type,
  id,
  status_code,
  content
FROM net._http_response
WHERE content LIKE '%14a914ef-e323-4e0e-8701-8e008422f927%'
   OR (content LIKE '%refundsIssued%' AND content LIKE '%348%')
ORDER BY id DESC
LIMIT 5;

