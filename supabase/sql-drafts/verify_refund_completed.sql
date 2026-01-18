-- ==============================================================================
-- Verify Refund Was Completed
-- ==============================================================================

-- Check the penalty record
SELECT 
  'Penalty Record' AS check_type,
  user_id,
  week_start_date,
  needs_reconciliation,
  reconciliation_delta_cents,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents,
  settlement_status,
  CASE 
    WHEN needs_reconciliation = false AND refund_amount_cents >= ABS(reconciliation_delta_cents) THEN '✅ Reconciliation complete - Refund issued'
    WHEN needs_reconciliation = false THEN '✅ Reconciliation complete (no action needed)'
    WHEN refund_amount_cents > 0 AND refund_amount_cents < ABS(reconciliation_delta_cents) THEN '⚠️ Partial refund issued: ' || refund_amount_cents || ' of ' || ABS(reconciliation_delta_cents) || ' cents'
    WHEN needs_reconciliation = true AND reconciliation_delta_cents < 0 THEN '⏳ Still needs refund: ' || ABS(reconciliation_delta_cents) || ' cents'
    WHEN needs_reconciliation = true AND reconciliation_delta_cents > 0 THEN '⏳ Still needs charge: ' || reconciliation_delta_cents || ' cents'
    ELSE '❓ Status unclear'
  END AS result
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- Check the queue entry
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
    WHEN status = 'processing' THEN '🔄 Processing'
    WHEN status = 'pending' THEN '⏳ Pending'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown')
    ELSE '❓ ' || status
  END AS result
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC
LIMIT 1;

-- Check if payment record was created
SELECT 
  'Payment Record' AS check_type,
  id,
  payment_type,
  amount_cents,
  status,
  stripe_payment_intent_id,
  stripe_charge_id,
  created_at
FROM payments
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
  AND payment_type = 'penalty_refund'
ORDER BY created_at DESC
LIMIT 1;

