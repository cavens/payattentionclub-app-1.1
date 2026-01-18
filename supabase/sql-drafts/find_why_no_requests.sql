-- ==============================================================================
-- Find Why net.http_post Is Not Being Called
-- ==============================================================================

-- Query 3: Manually test the function (this will show errors)
DO $$
DECLARE
  v_notice text;
BEGIN
  PERFORM public.process_reconciliation_queue();
  RAISE NOTICE '✅ Function executed without errors';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed: %', SQLERRM;
    RAISE NOTICE 'Error state: %', SQLSTATE;
END $$;

-- Query 4: Check queue entry status (is it being found?)
SELECT 
  'Queue Entry Status' AS check_type,
  id,
  user_id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  created_at,
  processed_at,
  CASE 
    WHEN status = 'pending' THEN '✅ Should be processed'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '⚠️ Stuck - should retry'
    WHEN status = 'processing' THEN '🔄 Currently processing'
    WHEN status = 'completed' THEN '✅ Already completed'
    WHEN status = 'failed' THEN '❌ Failed'
    ELSE '❓ ' || status
  END AS status_display,
  -- Check if it matches the WHERE clause
  CASE 
    WHEN status = 'pending' THEN '✅ Matches WHERE clause'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ Matches WHERE clause (stuck)'
    ELSE '❌ Does NOT match WHERE clause'
  END AS matches_where_clause
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Query 5: Check if ANY entries match the WHERE clause
SELECT 
  'Entries Matching WHERE Clause' AS check_type,
  COUNT(*) AS count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found ' || COUNT(*) || ' entries to process'
    ELSE '❌ No entries match WHERE clause (status=pending OR status=processing AND processed_at < NOW() - 5 min)'
  END AS status
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes');

-- Query 6: Check app_config values (maybe function is returning early)
SELECT 
  'App Config Check' AS check_type,
  key,
  CASE 
    WHEN key IN ('service_role_key', 'supabase_url', 'reconciliation_secret') THEN
      CASE 
        WHEN value IS NULL THEN '❌ NULL - Function will return early!'
        WHEN LENGTH(value) = 0 THEN '❌ Empty - Function will return early!'
        ELSE '✅ Set (' || LENGTH(value) || ' chars)'
      END
    ELSE 
      value
  END AS value_status
FROM app_config
WHERE key IN ('service_role_key', 'supabase_url', 'reconciliation_secret', 'testing_mode')
ORDER BY key;

