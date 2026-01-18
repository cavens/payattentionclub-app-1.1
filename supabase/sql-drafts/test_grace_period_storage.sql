-- ==============================================================================
-- Test: Verify week_grace_expires_at is populated correctly
-- ==============================================================================
-- This script tests that the updated rpc_create_commitment function
-- correctly calculates and stores week_grace_expires_at
-- ==============================================================================

-- Step 1: Check current testing mode
SELECT 
  key,
  value,
  description
FROM public.app_config
WHERE key = 'testing_mode';

-- Step 2: Create a test commitment in TESTING MODE
-- (This will use deadline_timestamp, so grace should be +1 minute)
DO $$
DECLARE
  v_test_user_id uuid := '11111111-1111-1111-1111-111111111111'; -- Test user from rpc_setup_test_data
  v_deadline_ts timestamptz := NOW() + INTERVAL '3 minutes'; -- Testing mode: 3 min deadline
  v_grace_expected timestamptz := v_deadline_ts + INTERVAL '1 minute'; -- Should be +1 minute
  v_commitment_id uuid;
  v_result json;
BEGIN
  -- Create commitment with deadline_timestamp (testing mode)
  SELECT public.rpc_create_commitment(
    p_deadline_date := CURRENT_DATE,
    p_limit_minutes := 30,
    p_penalty_per_minute_cents := 100,
    p_app_count := 1,
    p_apps_to_limit := '["com.example.app"]'::jsonb,
    p_saved_payment_method_id := 'pm_test_123',
    p_deadline_timestamp := v_deadline_ts
  ) INTO v_result;
  
  -- Extract commitment ID from result
  v_commitment_id := (v_result->>'id')::uuid;
  
  RAISE NOTICE 'Created commitment ID: %', v_commitment_id;
  RAISE NOTICE 'Expected grace expires at: %', v_grace_expected;
END $$;

-- Step 3: Verify the commitment has week_grace_expires_at set correctly
SELECT 
  id,
  week_end_date,
  week_end_timestamp,
  week_grace_expires_at,
  CASE 
    WHEN week_end_timestamp IS NOT NULL THEN 
      EXTRACT(EPOCH FROM (week_grace_expires_at - week_end_timestamp)) / 60
    ELSE NULL
  END AS grace_period_minutes,
  created_at
FROM public.commitments
WHERE user_id = '11111111-1111-1111-1111-111111111111'
ORDER BY created_at DESC
LIMIT 1;

-- Expected result for testing mode:
-- - week_end_timestamp: Should be set (the deadline timestamp)
-- - week_grace_expires_at: Should be exactly 1 minute after week_end_timestamp
-- - grace_period_minutes: Should be 1.0

-- Step 4: Test NORMAL MODE (no deadline_timestamp)
-- First, ensure testing_mode is false
UPDATE public.app_config
SET value = 'false'
WHERE key = 'testing_mode';

-- Create commitment without deadline_timestamp (normal mode)
DO $$
DECLARE
  v_test_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_monday_date date;
  v_result json;
BEGIN
  -- Calculate next Monday
  v_monday_date := CURRENT_DATE + (8 - EXTRACT(DOW FROM CURRENT_DATE)::int) % 7;
  IF EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN
    v_monday_date := CURRENT_DATE + 7;
  END IF;
  
  -- Create commitment without deadline_timestamp (normal mode)
  SELECT public.rpc_create_commitment(
    p_deadline_date := v_monday_date,
    p_limit_minutes := 30,
    p_penalty_per_minute_cents := 100,
    p_app_count := 1,
    p_apps_to_limit := '["com.example.app"]'::jsonb,
    p_saved_payment_method_id := 'pm_test_123',
    p_deadline_timestamp := NULL  -- Normal mode
  ) INTO v_result;
  
  RAISE NOTICE 'Created normal mode commitment';
END $$;

-- Step 5: Verify normal mode commitment
SELECT 
  id,
  week_end_date,
  week_end_timestamp,
  week_grace_expires_at,
  CASE 
    WHEN week_grace_expires_at IS NOT NULL AND week_end_date IS NOT NULL THEN
      -- Calculate if grace is Tuesday 12:00 ET (1 day after Monday)
      EXTRACT(EPOCH FROM (week_grace_expires_at - (week_end_date::timestamp AT TIME ZONE 'America/New_York' + INTERVAL '12 hours'))) / 3600
    ELSE NULL
  END AS grace_period_hours,
  created_at
FROM public.commitments
WHERE user_id = '11111111-1111-1111-1111-111111111111'
  AND week_end_timestamp IS NULL  -- Normal mode commitment
ORDER BY created_at DESC
LIMIT 1;

-- Expected result for normal mode:
-- - week_end_timestamp: Should be NULL
-- - week_grace_expires_at: Should be Tuesday 12:00 ET (1 day after Monday deadline)
-- - grace_period_hours: Should be approximately 24.0

-- Step 6: Cleanup (optional)
-- DELETE FROM public.commitments
-- WHERE user_id = '11111111-1111-1111-1111-111111111111'
--   AND created_at > NOW() - INTERVAL '10 minutes';

