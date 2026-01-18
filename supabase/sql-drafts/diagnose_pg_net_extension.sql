-- ==============================================================================
-- Diagnose pg_net Extension Setup
-- ==============================================================================
-- This checks if pg_net extension is properly installed and accessible
-- Based on the issue from Monday the 12th about extension signature problems
-- ==============================================================================

-- 1. Check if pg_net extension exists and where it's installed
SELECT 
  'Extension Status' AS check_type,
  extname AS extension_name,
  extnamespace::regnamespace AS schema_name,
  extversion AS version
FROM pg_extension
WHERE extname = 'pg_net';

-- Expected: Should show pg_net installed in 'public' or 'net' schema

-- 2. Check if net.http_post function exists and its signature
SELECT 
  'Function Signature' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND n.nspname IN ('net', 'public')
ORDER BY n.nspname;

-- Expected: Should show http_post function in 'net' or 'public' schema

-- 3. Check current search_path setting
SHOW search_path;

-- Expected: Should include 'net' or 'public' schema

-- 4. Test if we can call net.http_post (this will fail if extension not accessible)
-- Commented out to avoid making actual HTTP request
/*
SELECT net.http_post(
  url := 'https://httpbin.org/post',
  headers := jsonb_build_object('Content-Type', 'application/json'),
  body := '{}'::jsonb
);
*/

-- 5. Check if extension needs to be created in public schema
-- Settlement migration does: CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
-- But reconciliation function just sets search_path

-- 6. Compare with working settlement function
-- Settlement: CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
-- Settlement: Uses named parameters: url :=, headers :=, body :=
-- Reconciliation: No explicit extension creation, just search_path
-- Reconciliation: Uses named parameters: url :=, headers :=, body :=

-- POTENTIAL ISSUE: If extension is in 'net' schema but search_path doesn't include it,
-- or if extension needs to be explicitly in 'public' schema for cron jobs

