-- ==============================================================================
-- Check pg_net Extension Location
-- ==============================================================================
-- This will show where the extension is actually installed
-- ==============================================================================

-- 1. Check extension location
SELECT 
  'Extension Location' AS check_type,
  extname AS extension_name,
  extnamespace::regnamespace AS schema_name,
  extversion AS version,
  CASE 
    WHEN extnamespace::regnamespace::text = 'public' THEN '✅ In public schema (good)'
    WHEN extnamespace::regnamespace::text = 'net' THEN '⚠️ In net schema (need to ensure search_path includes it)'
    ELSE '❓ In ' || extnamespace::regnamespace::text || ' schema (unexpected)'
  END AS status
FROM pg_extension
WHERE extname = 'pg_net';

-- 2. Check if http_post function exists and where
SELECT 
  'Function Location' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  CASE 
    WHEN n.nspname = 'public' THEN '✅ In public schema'
    WHEN n.nspname = 'net' THEN '⚠️ In net schema (need search_path)'
    ELSE '❓ In ' || n.nspname || ' schema'
  END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND (n.nspname = 'net' OR n.nspname = 'public' OR n.nspname = 'extensions')
ORDER BY n.nspname;

-- 3. Current search_path (you already ran this)
-- Shows: "$user", public, extensions
-- Missing: 'net' schema!

-- 4. The problem:
-- If extension is in 'net' schema but search_path doesn't include 'net',
-- then net.http_post won't be found!
-- 
-- Solutions:
-- A. Create extension in public schema (like settlement does)
-- B. Ensure search_path includes 'net' (function tries to do this but might not work in cron)
-- C. Use fully qualified name: public.net.http_post or net.http_post with proper search_path

