-- ==============================================================================
-- Verify Function Was Updated
-- ==============================================================================

-- Check if the function includes the Authorization header fix
SELECT 
  'Function Check' AS check_type,
  CASE 
    WHEN prosrc LIKE '%Authorization%' AND prosrc LIKE '%Bearer%' AND prosrc LIKE '%x-reconciliation-secret%' THEN '✅ Function includes both Authorization and x-reconciliation-secret headers'
    WHEN prosrc LIKE '%Authorization%' AND prosrc LIKE '%Bearer%' THEN '⚠️ Function has Authorization but might be missing x-reconciliation-secret logic'
    WHEN prosrc LIKE '%x-reconciliation-secret%' AND NOT prosrc LIKE '%Authorization%' THEN '❌ Function has x-reconciliation-secret but missing Authorization header (OLD VERSION)'
    ELSE '❓ Cannot determine function version'
  END AS status,
  -- Show a snippet of the function code around the headers
  SUBSTRING(prosrc FROM POSITION('request_headers' IN prosrc) FOR 200) AS header_code_snippet
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'process_reconciliation_queue'
  AND n.nspname = 'public';

-- Also check if the function exists and is accessible
SELECT 
  'Function Exists' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  CASE 
    WHEN p.proname = 'process_reconciliation_queue' THEN '✅ Function exists'
    ELSE '❌ Function not found'
  END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'process_reconciliation_queue'
  AND n.nspname = 'public';

