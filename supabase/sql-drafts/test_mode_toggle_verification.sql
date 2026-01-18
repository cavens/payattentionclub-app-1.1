-- ==============================================================================
-- Verify Mode Toggle Changes
-- ==============================================================================
-- This script checks if both app_config and Edge Function behavior reflect
-- the testing mode changes. Run this after toggling mode in the dashboard.
-- ==============================================================================

-- 1. Check app_config.testing_mode
SELECT 
  'app_config.testing_mode' AS source,
  key,
  value,
  CASE 
    WHEN value = 'true' THEN '✅ Testing mode ON'
    WHEN value = 'false' THEN '✅ Testing mode OFF'
    ELSE '❌ Unknown value'
  END AS status,
  updated_at
FROM app_config
WHERE key = 'testing_mode';

-- 2. Check if PAT is configured (needed for secret updates)
SELECT 
  'PAT Configuration' AS check_type,
  CASE 
    WHEN EXISTS (SELECT 1 FROM app_config WHERE key = 'supabase_access_token' AND value IS NOT NULL AND value != '') 
    THEN '✅ PAT is configured'
    ELSE '❌ PAT is missing'
  END AS status;

-- 3. Check recent app_config updates
SELECT 
  'Recent Updates' AS check_type,
  key,
  value,
  updated_at,
  NOW() - updated_at AS time_since_update
FROM app_config
WHERE key IN ('testing_mode', 'supabase_access_token')
ORDER BY updated_at DESC;

-- 4. Check cron job status (settlement cron should respect testing mode)
SELECT 
  'Cron Job Check' AS check_type,
  jobname,
  schedule,
  active,
  CASE 
    WHEN jobname = 'Testing-Settlement' THEN 'This should only run when testing_mode = true'
    WHEN jobname = 'Weekly-Settlement' THEN 'This should only run when testing_mode = false'
    ELSE 'Other cron job'
  END AS note
FROM cron.job
WHERE jobname IN ('Testing-Settlement', 'Weekly-Settlement')
ORDER BY jobname;

-- ==============================================================================
-- Expected Results:
-- ==============================================================================
-- 1. app_config.testing_mode should show current mode (true/false)
-- 2. PAT should be configured (for automatic secret updates)
-- 3. Recent updates should show when testing_mode was last changed
-- 4. Cron jobs should be active and scheduled correctly
-- ==============================================================================

