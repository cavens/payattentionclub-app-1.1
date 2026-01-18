-- ==============================================================================
-- Next Steps After Creating Extension in Public Schema
-- ==============================================================================

-- 1. Verify extension is now in public schema
SELECT 
  extname,
  extnamespace::regnamespace AS schema_name,
  CASE 
    WHEN extnamespace::regnamespace::text = 'public' THEN '✅ Good - in public schema'
    ELSE '⚠️ Still in ' || extnamespace::regnamespace::text || ' schema'
  END AS status
FROM pg_extension
WHERE extname = 'pg_net';

-- 2. Check if http_post function exists in both schemas (might have duplicates)
SELECT 
  n.nspname AS schema_name,
  p.proname AS function_name,
  'Function exists in ' || n.nspname || ' schema' AS note
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND (n.nspname = 'net' OR n.nspname = 'public')
ORDER BY n.nspname;

-- 3. If extension is now in public, the function should be accessible
-- The function call `net.http_post(...)` should now work because:
-- - Extension is in public schema
-- - public is always in search_path
-- - Function should be accessible as net.http_post

-- 4. Next: Reset the stuck queue entry and test
-- UPDATE reconciliation_queue
-- SET status = 'pending', processed_at = NULL
-- WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- 5. Wait 1-2 minutes and check if quick-handler is called
-- Check quick-handler logs in Supabase Dashboard

