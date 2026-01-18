-- ==============================================================================
-- Check pg_net Worker Status and Request Storage
-- ==============================================================================

-- Check 1: Are there ANY requests in the queue at all?
SELECT 
  'Total Requests' AS check_type,
  COUNT(*) AS total_count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found ' || COUNT(*) || ' requests'
    ELSE '❌ No requests in queue at all'
  END AS status
FROM net.http_request_queue;

-- Check 2: Check all tables/views in net schema
SELECT 
  'Tables in net schema' AS check_type,
  table_name,
  table_type
FROM information_schema.tables
WHERE table_schema = 'net'
ORDER BY table_name;

-- Check 3: Check if there's a different table for completed requests
-- Some pg_net versions have http_request (completed) vs http_request_queue (pending)
SELECT 
  'Completed Requests' AS check_type,
  COUNT(*) AS count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found ' || COUNT(*) || ' completed requests'
    ELSE '❌ No completed requests table or empty'
  END AS status
FROM information_schema.tables
WHERE table_schema = 'net' 
  AND table_name = 'http_request';

-- Check 4: If http_request table exists, check it
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'net' AND table_name = 'http_request'
  ) THEN
    RAISE NOTICE 'http_request table exists - checking for requests';
  ELSE
    RAISE NOTICE 'http_request table does NOT exist';
  END IF;
END $$;

-- Check 5: Check pg_net extension version and status
SELECT 
  'Extension Info' AS check_type,
  extname,
  extversion,
  extnamespace::regnamespace AS schema_name
FROM pg_extension
WHERE extname = 'pg_net';

-- Check 6: Check if net.http_post function exists and is accessible
SELECT 
  'Function Check' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  CASE 
    WHEN n.nspname = 'net' THEN '✅ Function exists in net schema'
    WHEN n.nspname = 'public' THEN '✅ Function exists in public schema'
    ELSE '❓ Function in ' || n.nspname || ' schema'
  END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND (n.nspname = 'net' OR n.nspname = 'public');

