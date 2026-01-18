-- ==============================================================================
-- Check Penalty Record and Refund Status
-- ==============================================================================
-- Run this in Supabase SQL Editor to check if refund was issued
-- ==============================================================================

-- Replace these values with your actual user_id and week_start_date
\set user_id '9edd63d4-84ce-47f2-8b60-eda484d28a12'
\set week_start_date '2026-01-17'

-- 1. Check penalty record
SELECT 
  id,
  user_id,
  week_start_date,
  total_penalty_cents,
  actual_amount_cents,
  charged_amount_cents,
  refund_amount_cents,
  status,
  settlement_status,
  charge_payment_intent_id,
  refund_payment_intent_id,
  charged_at,
  refund_issued_at,
  needs_reconciliation,
  reconciliation_delta_cents,
  last_updated,
  -- Calculate net charge
  (charged_amount_cents - COALESCE(refund_amount_cents, 0)) AS net_charge_cents
FROM public.user_week_penalties
WHERE user_id = :'user_id'::uuid
  AND week_start_date = :'week_start_date'::date
ORDER BY last_updated DESC;

-- 2. Check refund payment records
SELECT 
  id,
  user_id,
  week_start_date,
  amount_cents,
  currency,
  stripe_payment_intent_id,
  stripe_charge_id,
  status,
  payment_type,
  created_at,
  updated_at
FROM public.payments
WHERE user_id = :'user_id'::uuid
  AND week_start_date = :'week_start_date'::date
  AND payment_type = 'penalty_refund'
ORDER BY created_at DESC;

-- 3. Check reconciliation queue entry
SELECT 
  id,
  user_id,
  week_start_date,
  reconciliation_delta_cents,
  status,
  created_at,
  processed_at,
  error_message,
  retry_count
FROM public.reconciliation_queue
WHERE user_id = :'user_id'::uuid
  AND week_start_date = :'week_start_date'::date
ORDER BY created_at DESC;

-- 4. Summary: Expected vs Actual
SELECT 
  'Penalty Record' AS source,
  charged_amount_cents AS "Charged ($)",
  actual_amount_cents AS "Actual ($)",
  refund_amount_cents AS "Refund ($)",
  (charged_amount_cents - COALESCE(refund_amount_cents, 0)) AS "Net Charge ($)",
  reconciliation_delta_cents AS "Expected Refund ($)",
  CASE 
    WHEN refund_amount_cents = ABS(reconciliation_delta_cents) THEN '✅ Refund matches'
    WHEN refund_amount_cents > 0 THEN '⚠️  Refund issued but amount differs'
    ELSE '❌ Refund not issued'
  END AS status
FROM public.user_week_penalties
WHERE user_id = :'user_id'::uuid
  AND week_start_date = :'week_start_date'::date
ORDER BY last_updated DESC
LIMIT 1;


