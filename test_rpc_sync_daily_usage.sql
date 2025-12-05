-- Test script for rpc_sync_daily_usage
-- Run this in Supabase SQL Editor to test the batch sync function

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

-- Test 6: Late sync reconciliation (manual setup required)
-- 1. Ensure there is a row in user_week_penalties for your user with settlement_status
--    set to 'charged_worst_case' (or 'charged_actual') and charged_amount_cents > 0.
-- 2. Run the settlement job or update the row manually to mimic a worst-case charge.
-- 3. Call the RPC again with new usage for that same week:
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
      'date', to_char(week_end_date - INTERVAL '2 day', 'YYYY-MM-DD'),
      'used_minutes', 210,
      'week_start_date', to_char(week_end_date, 'YYYY-MM-DD')
    )
  )
)
FROM target_week;
-- 4. The response's processed_weeks array should now include the week with
--    "needs_reconciliation": true and the expected delta.

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

