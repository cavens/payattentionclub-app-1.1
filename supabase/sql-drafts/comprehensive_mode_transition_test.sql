-- ==============================================================================
-- Comprehensive Mode Transition Test
-- ==============================================================================
-- This script tests the complete transition cycle and checks for potential issues
-- ==============================================================================

-- Step 1: Pre-Transition State Check
SELECT 
  'Step 1: Pre-Transition State' AS step,
  key,
  value AS current_value,
  updated_at,
  NOW() - updated_at AS age
FROM app_config
WHERE key = 'testing_mode';

-- Step 2: Validate Configuration Before Transition
SELECT 
  'Step 2: Pre-Transition Validation' AS step,
  public.rpc_validate_mode_consistency() AS validation;

-- Step 3: Check Cron Jobs Status
SELECT 
  'Step 3: Cron Jobs Status' AS step,
  jobname,
  schedule,
  active,
  CASE 
    WHEN jobname = 'Testing-Settlement' THEN 'Should be active in testing mode'
    WHEN jobname = 'Weekly-Settlement' THEN 'Should be active in normal mode'
    ELSE 'Other cron job'
  END AS expected_behavior
FROM cron.job
WHERE jobname IN ('Testing-Settlement', 'Weekly-Settlement')
ORDER BY jobname;

-- Step 4: Check if week_end_timestamp column exists
SELECT 
  'Step 4a: Check week_end_timestamp Column' AS step,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public'
        AND table_name = 'commitments' 
        AND column_name = 'week_end_timestamp'
    ) THEN '✅ week_end_timestamp column exists'
    ELSE '⚠️ week_end_timestamp column does not exist (migration may not be applied)'
  END AS column_status;

-- Step 4b: Check Active Commitments
-- This will work whether or not week_end_timestamp exists
SELECT 
  'Step 4b: Active Commitments Check' AS step,
  COUNT(*) AS total_commitments,
  COUNT(CASE WHEN week_end_date IS NOT NULL THEN 1 END) AS with_week_end_date,
  COUNT(CASE WHEN week_grace_expires_at IS NOT NULL THEN 1 END) AS with_grace_expires,
  MIN(created_at) AS oldest_commitment,
  MAX(created_at) AS newest_commitment
FROM commitments
WHERE status = 'active';

-- Step 5: Check Recent Penalties (user_week_penalties doesn't have week_end_timestamp)
-- Instead, check by week_start_date and settlement status
SELECT 
  'Step 5: Recent Penalties Check' AS step,
  COUNT(*) AS total_penalties,
  COUNT(CASE WHEN settlement_status = 'settled' THEN 1 END) AS settled_penalties,
  COUNT(CASE WHEN needs_reconciliation = true THEN 1 END) AS needs_reconciliation,
  MIN(week_start_date) AS oldest_penalty_week,
  MAX(week_start_date) AS newest_penalty_week
FROM user_week_penalties
WHERE week_start_date >= CURRENT_DATE - INTERVAL '7 days';

-- ==============================================================================
-- AFTER TOGGLE TO NORMAL MODE (run Steps 6-10)
-- ==============================================================================

-- Step 6: Post-Transition State Check
SELECT 
  'Step 6: Post-Transition State (Normal Mode)' AS step,
  key,
  value AS current_value,
  updated_at,
  CASE 
    WHEN value = 'false' THEN '✅ Normal mode (correct)'
    ELSE '❌ Still in testing mode'
  END AS status
FROM app_config
WHERE key = 'testing_mode';

-- Step 7: Validate Configuration After Transition
SELECT 
  'Step 7: Post-Transition Validation (Normal Mode)' AS step,
  public.rpc_validate_mode_consistency() AS validation;

-- Step 8: Test call_settlement() Skips in Normal Mode
-- (Manually run this to verify)
SELECT 
  'Step 8: Test call_settlement() Behavior' AS step,
  'Run manually: SELECT public.call_settlement();' AS instruction,
  'Expected: Notice saying "Settlement cron skipped - not in testing mode"' AS expected_result;

-- Step 9: Test call_settlement_normal() Works
-- (Manually run this to verify)
SELECT 
  'Step 9: Test call_settlement_normal() Behavior' AS step,
  'Run manually: SELECT public.call_settlement_normal();' AS instruction,
  'Expected: Notice saying "Normal mode settlement triggered"' AS expected_result;

-- Step 10: Check for Timing Issues
-- Verify that new commitments would use normal mode timing (7 days, not 3 minutes)
SELECT 
  'Step 10: Timing Configuration Check' AS step,
  'Verify Edge Functions will use 7-day week, 24-hour grace' AS check_item,
  'This requires testing Edge Function behavior' AS note;

-- ==============================================================================
-- AFTER TOGGLE BACK TO TESTING MODE (run Steps 11-12)
-- ==============================================================================

-- Step 11: Post-Transition State Check (Testing Mode)
SELECT 
  'Step 11: Post-Transition State (Testing Mode)' AS step,
  key,
  value AS current_value,
  updated_at,
  CASE 
    WHEN value = 'true' THEN '✅ Testing mode (correct)'
    ELSE '❌ Still in normal mode'
  END AS status
FROM app_config
WHERE key = 'testing_mode';

-- Step 12: Final Validation
SELECT 
  'Step 12: Final Validation (Testing Mode)' AS step,
  public.rpc_validate_mode_consistency() AS validation;

-- ==============================================================================
-- Summary Checklist
-- ==============================================================================
-- ✅ app_config.testing_mode updates correctly
-- ✅ Edge Function secret TESTING_MODE updates (check manually in Dashboard)
-- ✅ Validation function shows valid: true after each transition
-- ✅ call_settlement() skips in normal mode
-- ✅ call_settlement_normal() works in normal mode
-- ✅ Cron jobs are active as expected
-- ✅ No errors in function logs
-- ==============================================================================

