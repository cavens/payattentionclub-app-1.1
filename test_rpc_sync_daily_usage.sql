-- Test script for rpc_sync_daily_usage
-- Run this in Supabase SQL Editor to test the batch sync function
--
SELECT
set_config('request.jwt.claim.sub',  '11111111-1111-1111-1111-111111111111', true),
set_config('request.jwt.claim.role', 'authenticated', true),
set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',  '11111111-1111-1111-1111-111111111111',
      'role', 'authenticated',
      'email','test-user-1@example.com'
    )::text,
    true
  );

WITH target_week AS (
  SELECT CASE
    WHEN EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN CURRENT_DATE            -- Monday
    WHEN EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN CURRENT_DATE + 1        -- Sunday → next Monday
    ELSE CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1)        -- Tue‑Sat → last Monday
  END::date AS week_end_date
)
SELECT public."rpc_sync_daily_usage"(
  jsonb_build_array(
    jsonb_build_object(
      'date', to_char(week_end_date - INTERVAL '3 day', 'YYYY-MM-DD'),
      'used_minutes', 120,
      'week_start_date', to_char(week_end_date, 'YYYY-MM-DD')
    )
  )
)
FROM target_week;

-- Test 2: Multiple entries for same week
WITH target_week AS (
  SELECT CASE
    WHEN EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN CURRENT_DATE
    WHEN EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN CURRENT_DATE + 1
    ELSE CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1)
  END::date AS week_end_date
)
SELECT public."rpc_sync_daily_usage"(
  jsonb_build_array(
    jsonb_build_object(
      'date', to_char(week_end_date - INTERVAL '4 day', 'YYYY-MM-DD'),
      'used_minutes', 100,
      'week_start_date', to_char(week_end_date, 'YYYY-MM-DD')
    ),
    jsonb_build_object(
      'date', to_char(week_end_date - INTERVAL '3 day', 'YYYY-MM-DD'),
      'used_minutes', 120,
      'week_start_date', to_char(week_end_date, 'YYYY-MM-DD')
    ),
    jsonb_build_object(
      'date', to_char(week_end_date - INTERVAL '2 day', 'YYYY-MM-DD'),
      'used_minutes', 90,
      'week_start_date', to_char(week_end_date, 'YYYY-MM-DD')
    )
  )
)
FROM target_week;

-- Test 3: Multiple entries across different weeks (if you have multiple commitments)
WITH target_weeks AS (
  SELECT
    CASE
      WHEN EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN CURRENT_DATE
      WHEN EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN CURRENT_DATE + 1
      ELSE CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1)
    END::date AS week_end_date,
    (CASE
      WHEN EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN CURRENT_DATE + 7
      WHEN EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN CURRENT_DATE + 8
      ELSE CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1) + 7
    END)::date AS next_week_end_date
)
SELECT public."rpc_sync_daily_usage"(
  jsonb_build_array(
    jsonb_build_object(
      'date', to_char(week_end_date - INTERVAL '2 day', 'YYYY-MM-DD'),
      'used_minutes', 100,
      'week_start_date', to_char(week_end_date, 'YYYY-MM-DD')
    ),
    jsonb_build_object(
      'date', to_char(next_week_end_date - INTERVAL '3 day', 'YYYY-MM-DD'),
      'used_minutes', 110,
      'week_start_date', to_char(next_week_end_date, 'YYYY-MM-DD')
    )
  )
)
FROM target_weeks;

-- Test 4: Invalid entry (should fail gracefully)
SELECT public."rpc_sync_daily_usage"(
  '[
    {
      "date": "2025-11-27",
      "used_minutes": 100,
      "week_start_date": "2025-12-01"
    },
    {
      "date": "invalid-date",
      "used_minutes": 50,
      "week_start_date": "2025-12-01"
    }
  ]'::jsonb
);

-- Test 5: Empty array
SELECT public."rpc_sync_daily_usage"('[]'::jsonb);

-- After running tests, verify the data was inserted:
-- SELECT * FROM public.daily_usage 
-- WHERE user_id = auth.uid() 
-- ORDER BY date DESC 
-- LIMIT 10;

-- Check weekly totals were recalculated:
-- SELECT * FROM public.user_week_penalties 
-- WHERE user_id = auth.uid() 
-- ORDER BY week_start_date DESC;

-- Check pool totals:
-- SELECT * FROM public.weekly_pools 
-- ORDER BY week_start_date DESC 
-- LIMIT 5;

-- 1. Run weekly-close so Test User 1 (1111-...) gets charged 150¢ (30 min over @ 5¢).
-- 2. Simulate the user opening the app late (actual usage only 120 min) by forcing the
--    week totals down to zero and flagging a -150¢ delta:
WITH target_week AS (
  SELECT CASE
    WHEN EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN CURRENT_DATE
    WHEN EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN CURRENT_DATE + 1
    ELSE CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1)
  END::date AS week_end_date
),
payment_intent AS (
  SELECT stripe_payment_intent_id
  FROM public.payments p
  WHERE p.user_id = '11111111-1111-1111-1111-111111111111'::uuid
    AND p.week_start_date = (SELECT week_end_date FROM target_week)
    AND p.stripe_payment_intent_id IS NOT NULL
    AND p.status NOT IN ('penalty_refund','penalty_adjustment')
  ORDER BY p.created_at DESC
  LIMIT 1
),
charge_baseline AS (
  SELECT uwp.user_id,
         uwp.week_start_date,
         COALESCE(
           NULLIF(uwp.charged_amount_cents, 0),
           NULLIF(uwp.total_penalty_cents, 0),
           150
         ) AS baseline_amount,
         CASE
           WHEN uwp.charge_payment_intent_id IS NOT NULL
             AND uwp.charge_payment_intent_id <> 'pi_stub_for_manual_testing'
           THEN uwp.charge_payment_intent_id
           ELSE pay.stripe_payment_intent_id
         END AS baseline_payment_intent
  FROM public.user_week_penalties uwp
  JOIN target_week tw
    ON tw.week_end_date = uwp.week_start_date
  LEFT JOIN payment_intent pay ON TRUE
  WHERE uwp.user_id = '11111111-1111-1111-1111-111111111111'::uuid
    AND uwp.week_start_date = (SELECT week_end_date FROM target_week)
    AND (
      uwp.charge_payment_intent_id IS NOT NULL
        AND uwp.charge_payment_intent_id <> 'pi_stub_for_manual_testing'
      OR pay.stripe_payment_intent_id IS NOT NULL
    )
  LIMIT 1
),
updated AS (
  UPDATE public.user_week_penalties uwp
  SET charged_amount_cents = cb.baseline_amount,
      actual_amount_cents = 0,
      reconciliation_delta_cents = 0 - cb.baseline_amount,
      reconciliation_reason = 'late_sync',
      charge_payment_intent_id = cb.baseline_payment_intent,
      needs_reconciliation = true,
      reconciliation_detected_at = NOW(),
      last_updated = NOW()
  FROM charge_baseline cb
  WHERE uwp.user_id = cb.user_id
    AND uwp.week_start_date = cb.week_start_date
  RETURNING uwp.*
)
SELECT json_build_object(
  'week_start_date', week_start_date,
  'charged_amount_cents', charged_amount_cents,
  'actual_amount_cents', actual_amount_cents,
  'reconciliation_delta_cents', reconciliation_delta_cents,
  'needs_reconciliation', needs_reconciliation
)
FROM updated;
-- 3. Verify the SELECT shows reconciliation_delta_cents = -150 and needs_reconciliation = true.
-- 4. Call quick-handler (dry run first, then live) to issue the refund.

-- Inspect reconciliation flags and timestamps:
-- SELECT week_start_date,
--        settlement_status,
--        charged_amount_cents,
--        actual_amount_cents,
--        needs_reconciliation,
--        reconciliation_delta_cents,
--        reconciliation_reason,
--        reconciliation_detected_at
-- FROM public.user_week_penalties
-- WHERE user_id = auth.uid()
-- ORDER BY week_start_date DESC
-- LIMIT 5;

-- Reconciliation handler smoke test (Step 4C)
-- 1. After setting needs_reconciliation=true (see above), grab a real Stripe PaymentIntent id
--    and update user_week_penalties.charge_payment_intent_id with it (test mode is fine).
-- 2. Call the `quick-handler` edge function:
--    - Supabase dashboard → Edge Functions → quick-handler → POST {"limit":5,"dryRun":true}
--    - Rerun with {"limit":5} to issue the refund/extra charge.
-- 3. Validate:
--    - user_week_penalties row now has needs_reconciliation=false and settlement_status updated.
--    - payments table contains a penalty_refund / penalty_adjustment row referencing the same week.
--    - Stripe dashboard shows the refund or incremental charge.

