-- ==============================================================================
-- Simple Mode Transition Test - Step by Step
-- ==============================================================================
-- Run each step separately, one at a time
-- ==============================================================================

-- ==============================================================================
-- PHASE 1: BEFORE TOGGLE
-- ==============================================================================

-- Step 1: Check current testing mode
SELECT 
  'Step 1: Current Testing Mode' AS step,
  key,
  value AS current_value,
  updated_at,
  NOW() - updated_at AS age
FROM app_config
WHERE key = 'testing_mode';

-- Step 2: Validate configuration
SELECT 
  'Step 2: Pre-Transition Validation' AS step,
  public.rpc_validate_mode_consistency() AS validation;

-- Step 3: Check cron jobs
SELECT 
  'Step 3: Cron Jobs Status' AS step,
  jobname,
  schedule,
  active
FROM cron.job
WHERE jobname IN ('Testing-Settlement', 'Weekly-Settlement')
ORDER BY jobname;

-- Step 4: Check active commitments
SELECT 
  'Step 4: Active Commitments' AS step,
  COUNT(*) AS total_active,
  MIN(created_at) AS oldest,
  MAX(created_at) AS newest
FROM commitments
WHERE status = 'active';

-- ==============================================================================
-- PHASE 2: TOGGLE TO NORMAL MODE (use dashboard)
-- ==============================================================================
-- After toggling, wait 5 seconds, then run Steps 5-7
-- ==============================================================================

-- Step 5: Check mode after toggle
SELECT 
  'Step 5: Mode After Toggle' AS step,
  key,
  value,
  CASE 
    WHEN value = 'false' THEN '✅ Normal mode'
    ELSE '❌ Still in testing mode'
  END AS status
FROM app_config
WHERE key = 'testing_mode';

-- Step 6: Validate after toggle
SELECT 
  'Step 6: Post-Transition Validation' AS step,
  public.rpc_validate_mode_consistency() AS validation;

-- Step 7: Test call_settlement() skips (run manually)
-- SELECT public.call_settlement();
-- Expected: Notice "Settlement cron skipped - not in testing mode"

-- Step 8: Test call_settlement_normal() works (run manually)
-- SELECT public.call_settlement_normal();
-- Expected: Notice "Normal mode settlement triggered"

-- ==============================================================================
-- PHASE 3: TOGGLE BACK TO TESTING MODE (use dashboard)
-- ==============================================================================
-- After toggling back, wait 5 seconds, then run Steps 9-10
-- ==============================================================================

-- Step 9: Check mode after toggle back
SELECT 
  'Step 9: Mode After Toggle Back' AS step,
  key,
  value,
  CASE 
    WHEN value = 'true' THEN '✅ Testing mode'
    ELSE '❌ Still in normal mode'
  END AS status
FROM app_config
WHERE key = 'testing_mode';

-- Step 10: Final validation
SELECT 
  'Step 10: Final Validation' AS step,
  public.rpc_validate_mode_consistency() AS validation;

