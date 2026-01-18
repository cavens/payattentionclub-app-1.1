-- Simple check: Does function send Authorization header?
SELECT 
  CASE 
    WHEN prosrc LIKE '%Authorization%' AND prosrc LIKE '%Bearer%' THEN '❌ Sends Authorization header (OLD)'
    WHEN prosrc LIKE '%x-reconciliation-secret%' AND NOT prosrc LIKE '%Authorization%' THEN '✅ Only x-reconciliation-secret (NEW)'
    ELSE '❓ Unknown'
  END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'process_reconciliation_queue'
  AND n.nspname = 'public';

