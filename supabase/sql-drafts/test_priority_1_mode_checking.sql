-- ==============================================================================
-- Test Priority 1: Standardized Mode Checking
-- ==============================================================================
-- This tests that preview-service (and all functions) correctly check
-- database (app_config) first, then fall back to env var
-- ==============================================================================

-- Step 1: Check current mode in database
SELECT 
  'Step 1: Current app_config.testing_mode' AS step,
  key,
  value,
  updated_at
FROM app_config 
WHERE key = 'testing_mode';

-- Step 2: Verify mode consistency
SELECT 
  'Step 2: Mode Consistency Check' AS step,
  public.rpc_validate_mode_consistency() AS validation_result;

-- Step 3: Test preview-service response
-- (This would be done via API call, not SQL)
-- Expected: preview-service should use database value, not stale constant

-- Step 4: Toggle mode and verify preview-service picks it up
-- (This would be done via dashboard toggle, then test preview-service again)

-- ==============================================================================
-- Manual Test Steps:
-- ==============================================================================
-- 1. Note current mode: Run Step 1 above
-- 2. Call preview-service API and check logs for mode value
-- 3. Toggle mode in dashboard
-- 4. Call preview-service again - should show new mode immediately
-- 5. Verify no stale constant values are used
-- ==============================================================================

