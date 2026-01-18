-- ==============================================================================
-- Check quick-handler Edge Function Status
-- ==============================================================================
-- This checks if the function exists and its configuration
-- Note: Edge Function visibility (public/private) must be checked in Supabase Dashboard
-- ==============================================================================

-- Check if we can see the function in the database
-- (Edge Functions are managed by Supabase, not directly in PostgreSQL)
SELECT 
  'quick-handler Edge Function' AS check_type,
  'Check Supabase Dashboard → Edge Functions → quick-handler → Settings → Visibility' AS instruction,
  'Should be Public for pg_net.http_post to work, or Private with proper authentication' AS note;

-- Check if app_config has the necessary keys for calling quick-handler
SELECT 
  key,
  CASE 
    WHEN key = 'service_role_key' THEN '***HIDDEN***'
    WHEN key = 'supabase_url' THEN value
    ELSE value
  END AS value,
  'Required for process_reconciliation_queue to call quick-handler' AS purpose
FROM app_config
WHERE key IN ('service_role_key', 'supabase_url', 'testing_mode')
ORDER BY key;

