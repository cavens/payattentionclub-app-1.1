-- ==============================================================================
-- Verify Environment Isolation (Staging vs Production)
-- Run this in Supabase Dashboard → SQL Editor
-- ==============================================================================

-- Step 1: Check which Supabase URL is configured in app_config
SELECT 
  key,
  CASE 
    WHEN value LIKE '%auqujbppoytkeqdsgrbl%' THEN '✅ STAGING'
    WHEN value LIKE '%whdftvcrtrsnefhprebj%' THEN '⚠️ PRODUCTION'
    ELSE '❓ UNKNOWN'
  END as environment,
  CASE 
    WHEN key = 'service_role_key' THEN '***HIDDEN***'
    ELSE value
  END as value,
  updated_at
FROM public.app_config
WHERE key IN ('supabase_url', 'service_role_key')
ORDER BY key;

-- Step 2: Check what URLs the functions would call
-- process_reconciliation_queue calls: supabase_url || '/functions/v1/quick-handler'
-- call_weekly_close calls: supabase_url || '/functions/v1/bright-service'
SELECT 
  'process_reconciliation_queue' as function_name,
  value || '/functions/v1/quick-handler' as would_call,
  CASE 
    WHEN value LIKE '%auqujbppoytkeqdsgrbl%' THEN '✅ STAGING'
    WHEN value LIKE '%whdftvcrtrsnefhprebj%' THEN '⚠️ PRODUCTION'
    ELSE '❓ UNKNOWN'
  END as environment
FROM public.app_config
WHERE key = 'supabase_url'
UNION ALL
SELECT 
  'call_weekly_close' as function_name,
  value || '/functions/v1/bright-service' as would_call,
  CASE 
    WHEN value LIKE '%auqujbppoytkeqdsgrbl%' THEN '✅ STAGING'
    WHEN value LIKE '%whdftvcrtrsnefhprebj%' THEN '⚠️ PRODUCTION'
    ELSE '❓ UNKNOWN'
  END as environment
FROM public.app_config
WHERE key = 'supabase_url';

-- Step 3: Check for any hardcoded URLs in function definitions
SELECT 
  p.proname as function_name,
  CASE 
    WHEN pg_get_functiondef(p.oid) LIKE '%whdftvcrtrsnefhprebj%' THEN '⚠️ HARDCODED PRODUCTION URL'
    WHEN pg_get_functiondef(p.oid) LIKE '%auqujbppoytkeqdsgrbl%' THEN '✅ HARDCODED STAGING URL'
    WHEN pg_get_functiondef(p.oid) LIKE '%supabase.co%' THEN '⚠️ HARDCODED URL (check manually)'
    ELSE '✅ No hardcoded URLs (uses app_config)'
  END as url_check
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('process_reconciliation_queue', 'call_weekly_close', 'rpc_sync_daily_usage');



