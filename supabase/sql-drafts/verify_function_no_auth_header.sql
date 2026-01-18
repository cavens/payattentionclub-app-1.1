-- ==============================================================================
-- Verify Function Doesn't Send Authorization Header
-- ==============================================================================

-- Check if the function includes Authorization header (OLD) or only x-reconciliation-secret (NEW)
SELECT 
  'Function Check' AS check_type,
  CASE 
    WHEN prosrc LIKE '%Authorization%' AND prosrc LIKE '%Bearer%' AND prosrc LIKE '%x-reconciliation-secret%' THEN '❌ OLD VERSION - Still sends Authorization header'
    WHEN prosrc LIKE '%x-reconciliation-secret%' AND NOT prosrc LIKE '%Authorization%' THEN '✅ NEW VERSION - Only sends x-reconciliation-secret'
    WHEN prosrc LIKE '%Authorization%' AND NOT prosrc LIKE '%x-reconciliation-secret%' THEN '❌ VERY OLD - Only Authorization, no secret'
    ELSE '❓ Cannot determine'
  END AS status,
  -- Show snippet around headers
  SUBSTRING(prosrc FROM POSITION('request_headers' IN prosrc) FOR 300) AS header_code_snippet
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'process_reconciliation_queue'
  AND n.nspname = 'public';

