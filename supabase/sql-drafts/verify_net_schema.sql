-- ==============================================================================
-- Verify net schema and pg_net setup
-- Run this in Supabase Dashboard → SQL Editor
-- ==============================================================================

-- Step 1: Check if net schema exists
SELECT 
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'net') 
    THEN '✅ net schema EXISTS'
    ELSE '❌ net schema DOES NOT EXIST'
  END as net_schema_status;

-- Step 2: Show net schema details (if it exists)
SELECT 
  nspname as schema_name,
  nspowner::regrole as owner,
  nspacl as permissions
FROM pg_namespace 
WHERE nspname = 'net';

-- Step 3: Check pg_net extension status
SELECT 
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net')
    THEN '✅ pg_net extension is INSTALLED'
    ELSE '❌ pg_net extension is NOT INSTALLED'
  END as pg_net_status;

-- Step 4: Show pg_net extension details
SELECT 
  extname as extension_name,
  nspname as extension_schema,
  extversion as version
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE extname = 'pg_net';

-- Step 5: Check if net.http_post function exists
SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE p.proname = 'http_post' AND n.nspname = 'net'
    )
    THEN '✅ net.http_post function EXISTS'
    ELSE '❌ net.http_post function DOES NOT EXIST'
  END as http_post_status;

-- Step 6: Show net.http_post function details (if it exists)
SELECT 
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as arguments,
  p.oid::regprocedure as full_function_name
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND n.nspname = 'net';

-- Step 7: List all non-system schemas (to see what's available)
SELECT 
  nspname as schema_name,
  nspowner::regrole as owner
FROM pg_namespace
WHERE nspname NOT LIKE 'pg_%'
  AND nspname != 'information_schema'
ORDER BY nspname;

-- Step 8: Try to call net.http_post directly (will show error if it doesn't exist)
DO $$
DECLARE
  test_result bigint;
BEGIN
  SELECT net.http_post(
    'https://example.com',
    '{}'::jsonb,
    '{}'::jsonb,
    1000
  ) INTO test_result;
  RAISE NOTICE '✅ SUCCESS: net.http_post is callable (request_id: %)', test_result;
EXCEPTION
  WHEN undefined_function THEN
    RAISE WARNING '❌ ERROR: net.http_post function does not exist';
  WHEN insufficient_privilege THEN
    RAISE WARNING '❌ ERROR: Insufficient privilege to call net.http_post';
  WHEN OTHERS THEN
    RAISE WARNING '❌ ERROR calling net.http_post: %', SQLERRM;
END;
$$;



