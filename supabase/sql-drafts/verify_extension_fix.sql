-- ==============================================================================
-- Verify pg_net Extension is Now in Public Schema
-- ==============================================================================
-- After running: CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
-- ==============================================================================

-- 1. Check extension location (should now show 'public')
SELECT 
  'Extension Location' AS check_type,
  extname AS extension_name,
  extnamespace::regnamespace AS schema_name,
  extversion AS version,
  CASE 
    WHEN extnamespace::regnamespace::text = 'public' THEN '✅ In public schema (correct!)'
    WHEN extnamespace::regnamespace::text = 'net' THEN '⚠️ Still in net schema - may need to drop and recreate'
    ELSE '❓ In ' || extnamespace::regnamespace::text || ' schema'
  END AS status
FROM pg_extension
WHERE extname = 'pg_net';

-- 2. Check if http_post function is now accessible in public schema
SELECT 
  'Function Accessibility' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  CASE 
    WHEN n.nspname = 'public' THEN '✅ In public schema - should be accessible'
    WHEN n.nspname = 'net' THEN '⚠️ Still in net schema - may need to reference as net.http_post'
    ELSE '❓ In ' || n.nspname || ' schema'
  END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND (n.nspname = 'net' OR n.nspname = 'public' OR n.nspname = 'extensions')
ORDER BY n.nspname;

-- 3. If extension is still in 'net' schema, you may need to:
--    DROP EXTENSION pg_net CASCADE;
--    CREATE EXTENSION pg_net WITH SCHEMA public;
--    (But be careful - CASCADE will drop dependent objects!)

-- 4. Test if function is now accessible (commented out to avoid actual HTTP call)
/*
SELECT net.http_post(
  url := 'https://httpbin.org/post',
  headers := jsonb_build_object('Content-Type', 'application/json'),
  body := '{}'::jsonb
);
*/

