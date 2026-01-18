-- ==============================================================================
-- Check All Reconciliation Status (Simple)
-- ==============================================================================

-- 1. Penalty Record
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

-- 2. Queue Entry
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
ORDER BY created_at DESC
LIMIT 1;

-- 3. Payment Record (already confirmed)
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

