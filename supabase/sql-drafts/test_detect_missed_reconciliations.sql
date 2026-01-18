-- Test the rpc_detect_missed_reconciliations function
-- This should detect the missed reconciliation for the user

SELECT * FROM public.rpc_detect_missed_reconciliations(10);

-- Check if it created the queue entry
SELECT 
  'Queue Entry After Detection' as check_type,
  id,
  user_id,
  week_start_date,
  reconciliation_delta_cents,
  status,
  created_at,
  processed_at
FROM public.reconciliation_queue
WHERE user_id = '6ad5c166-68a0-4a0d-8086-f54f245001e1'::uuid
  AND week_start_date = '2026-01-18'::date
ORDER BY created_at DESC;

-- Check if it updated the penalty record
SELECT 
  'Penalty Record After Detection' as check_type,
  user_id,
  week_start_date,
  settlement_status,
  charged_amount_cents,
  actual_amount_cents,
  needs_reconciliation,
  reconciliation_delta_cents,
  reconciliation_reason,
  reconciliation_detected_at
FROM public.user_week_penalties
WHERE user_id = '6ad5c166-68a0-4a0d-8086-f54f245001e1'::uuid
  AND week_start_date = '2026-01-18'::date;

