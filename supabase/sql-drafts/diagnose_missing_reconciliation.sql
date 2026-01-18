-- Diagnose why reconciliation wasn't detected for a specific user/week
-- Replace the user_id and week_start_date with the values from the verification result

\set user_id '6ad5c166-68a0-4a0d-8086-f54f245001e1'
\set week_start_date '2026-01-18'

-- Step 1: Check the current penalty record
SELECT 
  'Current Penalty Record' as check_type,
  user_id,
  week_start_date,
  settlement_status,
  charged_amount_cents,
  actual_amount_cents,
  needs_reconciliation,
  reconciliation_delta_cents,
  reconciliation_reason,
  reconciliation_detected_at,
  last_updated,
  CASE 
    WHEN settlement_status = ANY(ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial']) THEN '✅ Is settled status'
    ELSE '❌ Not a settled status'
  END as settlement_check,
  CASE 
    WHEN actual_amount_cents IS NOT NULL AND charged_amount_cents IS NOT NULL 
         AND actual_amount_cents != charged_amount_cents THEN 
      '✅ Delta should be: ' || (actual_amount_cents - charged_amount_cents) || ' cents'
    ELSE 'No delta (or missing values)'
  END as expected_delta
FROM public.user_week_penalties
WHERE user_id = :'user_id'::uuid
  AND week_start_date = :'week_start_date'::date;

-- Step 2: Check if there's a queue entry
SELECT 
  'Queue Entry Check' as check_type,
  id,
  user_id,
  week_start_date,
  reconciliation_delta_cents,
  status,
  created_at,
  processed_at,
  error_message,
  retry_count,
  CASE 
    WHEN status = 'pending' THEN '⏳ Still pending'
    WHEN status = 'processing' THEN '🔄 Processing'
    WHEN status = 'completed' THEN '✅ Completed'
    WHEN status = 'failed' THEN '❌ Failed'
    ELSE 'Unknown status'
  END as status_description
FROM public.reconciliation_queue
WHERE user_id = :'user_id'::uuid
  AND week_start_date = :'week_start_date'::date
ORDER BY created_at DESC;

-- Step 3: Check the commitment to get max_charge_cents
SELECT 
  'Commitment Check' as check_type,
  id,
  user_id,
  week_start_date,
  week_end_date,
  max_charge_cents,
  created_at
FROM public.commitments
WHERE user_id = :'user_id'::uuid
  AND week_end_date = :'week_start_date'::date
ORDER BY created_at DESC
LIMIT 1;

-- Step 4: Check daily_usage to see what actual usage was synced
SELECT 
  'Daily Usage Check' as check_type,
  COUNT(*) as usage_entry_count,
  COALESCE(SUM(penalty_cents), 0) as total_penalty_cents,
  MIN(date) as earliest_date,
  MAX(date) as latest_date
FROM public.daily_usage
WHERE user_id = :'user_id'::uuid
  AND date >= :'week_start_date'::date
  AND date <= :'week_start_date'::date + INTERVAL '6 days';

-- Step 5: Simulate what rpc_sync_daily_usage would calculate
WITH penalty_data AS (
  SELECT 
    settlement_status,
    COALESCE(charged_amount_cents, 0) as prev_charged,
    COALESCE(needs_reconciliation, false) as prev_needs_reconciliation
  FROM public.user_week_penalties
  WHERE user_id = :'user_id'::uuid
    AND week_start_date = :'week_start_date'::date
),
usage_data AS (
  SELECT COALESCE(SUM(penalty_cents), 0) as total_cents
  FROM public.daily_usage du
  JOIN public.commitments c ON du.commitment_id = c.id
  WHERE du.user_id = :'user_id'::uuid
    AND c.week_end_date = :'week_start_date'::date
    AND du.date >= c.week_start_date
    AND du.date <= c.week_end_date
),
commitment_data AS (
  SELECT COALESCE(max_charge_cents, 0) as max_charge
  FROM public.commitments
  WHERE user_id = :'user_id'::uuid
    AND week_end_date = :'week_start_date'::date
  LIMIT 1
)
SELECT 
  'Reconciliation Simulation' as check_type,
  pd.settlement_status,
  pd.prev_charged,
  ud.total_cents as raw_actual,
  cd.max_charge,
  LEAST(ud.total_cents, cd.max_charge) as capped_actual,
  CASE 
    WHEN pd.settlement_status = ANY(ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial']) THEN
      LEAST(ud.total_cents, cd.max_charge) - pd.prev_charged
    ELSE 0
  END as calculated_delta,
  CASE 
    WHEN pd.settlement_status = ANY(ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial']) 
         AND (LEAST(ud.total_cents, cd.max_charge) - pd.prev_charged) != 0 THEN '✅ Should need reconciliation'
    WHEN pd.settlement_status = ANY(ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial']) THEN 'No reconciliation needed (delta = 0)'
    ELSE '❌ Not settled yet - reconciliation detection skipped'
  END as reconciliation_should_be,
  pd.prev_needs_reconciliation as already_flagged,
  CASE 
    WHEN pd.settlement_status = ANY(ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial']) 
         AND (LEAST(ud.total_cents, cd.max_charge) - pd.prev_charged) != 0 
         AND NOT pd.prev_needs_reconciliation THEN '✅ Should create queue entry'
    WHEN pd.settlement_status = ANY(ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial']) 
         AND (LEAST(ud.total_cents, cd.max_charge) - pd.prev_charged) != 0 
         AND pd.prev_needs_reconciliation THEN '⚠️ Already flagged - queue entry might exist'
    ELSE 'No queue entry needed'
  END as queue_entry_should_be
FROM penalty_data pd
CROSS JOIN usage_data ud
CROSS JOIN commitment_data cd;

