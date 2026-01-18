-- ==============================================================================
-- Next Diagnostic Queries (After Cron Job Confirmed Running)
-- ==============================================================================

-- Query 2: Check if pg_net is creating HTTP requests
-- This will show if net.http_post is actually being called
SELECT 
  'pg_net Requests' AS check_type,
  id,
  url,
  method,
  status_code,
  content,
  created,
  CASE 
    WHEN status_code IS NULL THEN '⏳ Pending/Queued'
    WHEN status_code >= 200 AND status_code < 300 THEN '✅ Success'
    WHEN status_code >= 400 THEN '❌ Error: ' || status_code
    ELSE '❓ Status: ' || status_code
  END AS status_display
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY created DESC
LIMIT 10;

-- Query 3: Manually test the function (this will show any errors)
-- Run this to see what happens when the function executes
DO $$
DECLARE
  v_result text;
BEGIN
  PERFORM public.process_reconciliation_queue();
  RAISE NOTICE '✅ Function executed without errors';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed: %', SQLERRM;
    RAISE NOTICE 'Error details: %', SQLSTATE;
END $$;

-- Query 4: Check current queue entry status
SELECT 
  'Queue Entry' AS check_type,
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
  END AS status_display
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Query 5: Check if there are ANY pending entries
SELECT 
  'Pending Entries' AS check_type,
  COUNT(*) AS count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found ' || COUNT(*) || ' pending entries'
    ELSE '❌ No pending entries found'
  END AS status
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes');

-- Query 6: Compare with working settlement (see if bright-service requests are working)
SELECT 
  'Settlement Comparison' AS check_type,
  url,
  status_code,
  created,
  CASE 
    WHEN status_code IS NULL THEN '⏳ Pending'
    WHEN status_code >= 200 AND status_code < 300 THEN '✅ Success'
    ELSE '❌ Error: ' || status_code
  END AS status_display
FROM net.http_request_queue
WHERE url LIKE '%bright-service%'
ORDER BY created DESC
LIMIT 3;

