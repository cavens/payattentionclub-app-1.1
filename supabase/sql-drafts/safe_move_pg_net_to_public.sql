-- ==============================================================================
-- Safe Migration: Move pg_net Extension to Public Schema
-- ==============================================================================
-- This moves the extension from 'extensions' to 'public' schema
-- WARNING: This will temporarily drop the extension and recreate it
-- ==============================================================================

-- Step 1: Check dependencies first (run check_pg_net_dependencies.sql)
-- Make sure you understand what will be affected

-- Step 2: Drop the extension (this will drop the net schema and its functions)
-- The functions that USE net.http_post (like process_reconciliation_queue, call_settlement)
-- will remain but will be broken until we recreate the extension
DROP EXTENSION IF EXISTS pg_net CASCADE;

-- Step 3: Recreate in public schema (matches working settlement pattern)
CREATE EXTENSION pg_net WITH SCHEMA public;

-- Step 4: Verify it's now in public schema
SELECT 
  'Verification' AS check_type,
  extname,
  extnamespace::regnamespace AS schema_name,
  CASE 
    WHEN extnamespace::regnamespace::text = 'public' THEN '✅ Success - in public schema'
    ELSE '❌ Still in ' || extnamespace::regnamespace::text || ' schema'
  END AS status
FROM pg_extension
WHERE extname = 'pg_net';

-- Step 5: Verify net.http_post function is accessible
SELECT 
  'Function Check' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  CASE 
    WHEN n.nspname = 'net' THEN '✅ Function exists in net schema'
    WHEN n.nspname = 'public' THEN '✅ Function exists in public schema'
    ELSE '❓ Function in ' || n.nspname || ' schema'
  END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'http_post'
  AND (n.nspname = 'net' OR n.nspname = 'public')
ORDER BY n.nspname;

-- After this, your functions (process_reconciliation_queue, call_settlement) should work
-- because net.http_post will be accessible via the public schema context

