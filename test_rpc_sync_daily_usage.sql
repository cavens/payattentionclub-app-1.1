-- Test script for rpc_sync_daily_usage
-- Run this in Supabase SQL Editor to test the batch sync function

-- Test 1: Single entry sync
SELECT public."rpc_sync_daily_usage"(
  '[
    {
      "date": "2025-11-28",
      "used_minutes": 120,
      "week_start_date": "2025-12-01"
    }
  ]'::jsonb
);

-- Test 2: Multiple entries for same week
SELECT public."rpc_sync_daily_usage"(
  '[
    {
      "date": "2025-11-27",
      "used_minutes": 100,
      "week_start_date": "2025-12-01"
    },
    {
      "date": "2025-11-28",
      "used_minutes": 120,
      "week_start_date": "2025-12-01"
    },
    {
      "date": "2025-11-29",
      "used_minutes": 90,
      "week_start_date": "2025-12-01"
    }
  ]'::jsonb
);

-- Test 3: Multiple entries across different weeks (if you have multiple commitments)
SELECT public."rpc_sync_daily_usage"(
  '[
    {
      "date": "2025-11-27",
      "used_minutes": 100,
      "week_start_date": "2025-12-01"
    },
    {
      "date": "2025-12-04",
      "used_minutes": 110,
      "week_start_date": "2025-12-08"
    }
  ]'::jsonb
);

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



