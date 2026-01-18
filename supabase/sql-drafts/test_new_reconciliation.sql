-- ==============================================================================
-- Test New Reconciliation Entry
-- ==============================================================================

-- Check if queue entry exists for this new commitment
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
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC
LIMIT 1;

-- Manually trigger reconciliation
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Triggering process_reconciliation_queue()...';
  RAISE NOTICE '========================================';
  
  PERFORM public.process_reconciliation_queue();
  
  RAISE NOTICE '✅ Function completed';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed: %', SQLERRM;
END $$;

-- Check queue entry status after processing
SELECT 
  'Queue Entry After Processing' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at
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

-- Check if refund payment was created
SELECT 
  'Refund Payment' AS check_type,
  id,
  payment_type,
  amount_cents,
  status,
  stripe_payment_intent_id,
  stripe_charge_id,
  created_at
FROM payments
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18'
  AND payment_type = 'penalty_refund'
ORDER BY created_at DESC
LIMIT 1;

