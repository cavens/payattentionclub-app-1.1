-- ==============================================================================
-- Check Why Processing Entry Isn't Completing
-- ==============================================================================
-- The queue entry is in 'processing' status, which means:
-- 1. Cron job picked it up
-- 2. Called quick-handler via net.http_post
-- 3. But refund verification hasn't passed yet
-- ==============================================================================

-- Check the verification logic:
-- process_reconciliation_queue checks if refund_amount_cents >= ABS(reconciliation_delta_cents)
-- reconciliation_delta_cents = -361, so it needs refund_amount_cents >= 361

SELECT 
  'Verification Check' AS check_type,
  refund_amount_cents AS current_refund,
  361 AS required_refund,
  CASE 
    WHEN refund_amount_cents >= 361 THEN '✅ Refund sufficient - should mark as completed'
    WHEN refund_amount_cents > 0 THEN '⚠️ Partial refund issued (' || refund_amount_cents || ' cents) - needs ' || (361 - refund_amount_cents) || ' more'
    ELSE '❌ No refund issued yet (0 cents)'
  END AS status
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- Check if there are any Stripe refund payment intents
SELECT 
  'Stripe Refunds' AS check_type,
  id,
  amount_cents,
  currency,
  stripe_payment_intent_id,
  status,
  payment_type,
  created_at
FROM payments
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
  AND payment_type LIKE '%refund%'
ORDER BY created_at DESC;

-- The queue entry will stay in 'processing' until:
-- 1. quick-handler successfully issues a refund AND updates refund_amount_cents
-- 2. OR it's been processing for > 5 minutes and gets retried
-- 3. OR it fails and gets marked as 'failed'

-- Next steps:
-- 1. Check quick-handler logs in Supabase Dashboard
-- 2. Check if quick-handler was actually called (look for "settlement-reconcile invoked" log)
-- 3. Check for any errors in quick-handler logs

