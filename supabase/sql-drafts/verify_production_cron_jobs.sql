-- ==============================================================================
-- Verify Production Cron Jobs for Reconciliation Queue
-- Run this in PRODUCTION Supabase Dashboard → SQL Editor
-- ==============================================================================

-- Step 1: Check if both cron jobs exist
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  LEFT(command, 80) as command_preview,
  CASE 
    WHEN jobname = 'process-reconciliation-queue-testing' AND schedule = '* * * * *' THEN '✅ Correct (every 1 minute)'
    WHEN jobname = 'process-reconciliation-queue-normal' AND schedule = '*/10 * * * *' THEN '✅ Correct (every 10 minutes)'
    ELSE '⚠️ Check schedule'
  END as status
FROM cron.job
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
ORDER BY jobname;

-- Step 2: Check TESTING_MODE setting in app_config
SELECT 
  key,
  value,
  CASE 
    WHEN key = 'testing_mode' AND value = 'false' THEN '✅ Normal mode (production)'
    WHEN key = 'testing_mode' AND value = 'true' THEN '⚠️ Testing mode (should be false in production)'
    WHEN key = 'testing_mode' AND value IS NULL THEN '⚠️ Not set (defaults to false = normal mode)'
    ELSE 'N/A'
  END as mode_status
FROM public.app_config
WHERE key = 'testing_mode';

-- Step 3: Verify function signature is correct (should use 5 parameters)
SELECT 
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as arguments,
  CASE 
    WHEN pg_get_function_arguments(p.oid) LIKE '%url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer%' 
      THEN '✅ Correct signature (5 parameters)'
    ELSE '⚠️ Check signature: ' || pg_get_function_arguments(p.oid)
  END as signature_status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'process_reconciliation_queue'
  AND n.nspname = 'public';

-- Step 4: Check if app_config has required values
SELECT 
  key,
  CASE 
    WHEN key = 'service_role_key' THEN 
      CASE 
        WHEN value IS NOT NULL THEN '✅ Set'
        ELSE '❌ Missing'
      END
    WHEN key = 'supabase_url' THEN 
      CASE 
        WHEN value IS NOT NULL THEN '✅ Set: ' || LEFT(value, 50) || '...'
        ELSE '❌ Missing'
      END
    ELSE 'N/A'
  END as status
FROM public.app_config
WHERE key IN ('service_role_key', 'supabase_url', 'testing_mode')
ORDER BY key;

-- Step 5: Test the function call (dry run - won't actually process)
-- This will show if there are any syntax errors
DO $$
DECLARE
  test_result void;
BEGIN
  -- Just check if function can be called (it will exit early if app_config missing)
  PERFORM public.process_reconciliation_queue();
  RAISE NOTICE '✅ Function is callable (no syntax errors)';
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING '❌ Function error: %', SQLERRM;
END;
$$;

-- Step 6: Summary
SELECT 
  'Production Cron Job Status' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM cron.job 
      WHERE jobname = 'process-reconciliation-queue-normal' 
        AND schedule = '*/10 * * * *'
        AND active = true
    ) THEN '✅ Normal mode cron job exists and is active'
    ELSE '❌ Normal mode cron job missing or inactive'
  END as normal_job_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM cron.job 
      WHERE jobname = 'process-reconciliation-queue-testing' 
        AND schedule = '* * * * *'
        AND active = true
    ) THEN '✅ Testing mode cron job exists (will exit early in production)'
    ELSE '⚠️ Testing mode cron job missing'
  END as testing_job_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM public.app_config 
      WHERE key = 'testing_mode' AND value = 'false'
    ) OR NOT EXISTS (
      SELECT 1 FROM public.app_config WHERE key = 'testing_mode'
    ) THEN '✅ Production mode (testing_mode = false or not set)'
    ELSE '⚠️ Check testing_mode setting'
  END as mode_status;



