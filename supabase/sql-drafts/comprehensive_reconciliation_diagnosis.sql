-- ==============================================================================
-- Comprehensive Reconciliation Diagnosis
-- ==============================================================================
-- Run these queries to find out why quick-handler isn't being called
-- ==============================================================================

-- 1. CHECK: Is the cron job actually running?
SELECT 
  'Cron Job Status' AS check_type,
  jobid,
  jobname,
  schedule,
  active,
  CASE 
    WHEN active THEN '✅ Active'
    ELSE '❌ Inactive'
  END AS status
FROM cron.job
WHERE jobname LIKE '%reconciliation%'
ORDER BY jobname;

-- 2. CHECK: Recent cron job execution history (last 10 runs)
SELECT 
  'Cron Execution History' AS check_type,
  j.jobname,
  jr.runid,
  jr.job_pid,
  jr.database,
  jr.username,
  jr.command,
  jr.status,
  jr.return_message,
  jr.start_time,
  jr.end_time,
  CASE 
    WHEN jr.status = 'succeeded' THEN '✅ Succeeded'
    WHEN jr.status = 'failed' THEN '❌ Failed'
    WHEN jr.status = 'running' THEN '🔄 Running'
    ELSE '❓ ' || jr.status
  END AS status_display
FROM cron.job_run_details jr
JOIN cron.job j ON jr.jobid = j.jobid
WHERE j.jobname LIKE '%reconciliation%'
ORDER BY jr.start_time DESC
LIMIT 10;

-- 3. CHECK: Queue entry status
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
    WHEN status = 'pending' THEN '⏳ Pending'
    WHEN status = 'processing' THEN '🔄 Processing'
    WHEN status = 'completed' THEN '✅ Completed'
    WHEN status = 'failed' THEN '❌ Failed'
    ELSE '❓ ' || status
  END AS status_display,
  CASE 
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '⚠️ Stuck (processing > 5 min)'
    WHEN status = 'pending' THEN '✅ Ready to process'
    ELSE 'N/A'
  END AS action_needed
FROM reconciliation_queue
ORDER BY created_at DESC
LIMIT 5;

-- 4. CHECK: App config values (verify secrets are set)
SELECT 
  'App Config' AS check_type,
  key,
  CASE 
    WHEN key LIKE '%secret%' OR key LIKE '%key%' THEN 
      CASE 
        WHEN value IS NULL THEN '❌ NULL'
        WHEN LENGTH(value) = 0 THEN '❌ Empty'
        ELSE '✅ Set (' || LENGTH(value) || ' chars)'
      END
    ELSE 
      CASE 
        WHEN value IS NULL THEN '❌ NULL'
        ELSE '✅ ' || value
      END
  END AS value_status
FROM app_config
WHERE key IN ('service_role_key', 'supabase_url', 'reconciliation_secret', 'testing_mode')
ORDER BY key;

-- 5. CHECK: pg_net extension location (verify it's in public)
SELECT 
  'Extension Location' AS check_type,
  extname,
  extnamespace::regnamespace AS schema_name,
  CASE 
    WHEN extnamespace::regnamespace::text = 'public' THEN '✅ In public schema'
    ELSE '❌ In ' || extnamespace::regnamespace::text || ' schema'
  END AS status
FROM pg_extension
WHERE extname = 'pg_net';

-- 6. CHECK: net.http_post function accessibility
SELECT 
  'Function Accessibility' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
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

-- 7. CHECK: pg_net request logs (see if any requests were made)
SELECT 
  'pg_net Request Logs' AS check_type,
  id,
  url,
  method,
  headers,
  body,
  status_code,
  content,
  created,
  CASE 
    WHEN status_code IS NULL THEN '⏳ Pending'
    WHEN status_code >= 200 AND status_code < 300 THEN '✅ Success'
    WHEN status_code >= 400 THEN '❌ Error'
    ELSE '❓ Status: ' || status_code
  END AS status_display
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY created DESC
LIMIT 10;

-- 8. CHECK: Test manual function call (this will show errors)
-- Uncomment to test:
/*
DO $$
DECLARE
  result text;
BEGIN
  PERFORM public.process_reconciliation_queue();
  RAISE NOTICE 'Function executed successfully';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Function failed: %', SQLERRM;
END $$;
*/

-- 9. CHECK: Search path in function context
SELECT 
  'Search Path Check' AS check_type,
  current_setting('search_path') AS current_search_path,
  CASE 
    WHEN current_setting('search_path') LIKE '%net%' THEN '✅ net in search_path'
    ELSE '❌ net NOT in search_path'
  END AS status;

