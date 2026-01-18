-- ==============================================================================
-- Check Why Function Loop Isn't Executing
-- ==============================================================================

-- Query 4: Check queue entry status
SELECT 
  id,
  status,
  processed_at,
  error_message,
  created_at,
  CASE 
    WHEN status = 'pending' THEN '✅ Should be processed'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '⚠️ Stuck - should retry'
    WHEN status = 'processing' THEN '🔄 Currently processing (processed ' || EXTRACT(EPOCH FROM (NOW() - processed_at))::int || ' seconds ago)'
    WHEN status = 'completed' THEN '✅ Already completed'
    WHEN status = 'failed' THEN '❌ Failed'
    ELSE '❓ ' || status
  END AS status_display,
  -- Check if it matches the WHERE clause in the function
  CASE 
    WHEN status = 'pending' THEN '✅ MATCHES WHERE clause'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ MATCHES WHERE clause (stuck)'
    ELSE '❌ Does NOT match WHERE clause'
  END AS matches_where_clause
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Query 5: Check if ANY entries match the WHERE clause
SELECT 
  COUNT(*) AS matching_entries,
  COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
  COUNT(*) FILTER (WHERE status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes') AS stuck_count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found ' || COUNT(*) || ' entries to process'
    ELSE '❌ No entries match WHERE clause - Function loop will not execute!'
  END AS status
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes');

-- Query 6: Check app_config (function might return early)
SELECT 
  key,
  CASE 
    WHEN value IS NULL THEN '❌ NULL'
    WHEN LENGTH(value) = 0 THEN '❌ Empty'
    WHEN key IN ('service_role_key', 'reconciliation_secret') THEN '✅ Set (' || LENGTH(value) || ' chars)'
    ELSE '✅ ' || value
  END AS value_status,
  CASE 
    WHEN key IN ('service_role_key', 'supabase_url') AND value IS NULL THEN '⚠️ Function will RETURN EARLY!'
    ELSE 'OK'
  END AS impact
FROM app_config
WHERE key IN ('service_role_key', 'supabase_url', 'reconciliation_secret', 'testing_mode')
ORDER BY key;

-- Query 7: Show ALL queue entries (to see what's there)
SELECT 
  id,
  status,
  user_id,
  week_start_date,
  created_at,
  processed_at,
  retry_count,
  error_message
FROM reconciliation_queue
ORDER BY created_at DESC
LIMIT 10;

