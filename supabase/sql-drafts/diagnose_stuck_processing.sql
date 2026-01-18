-- ==============================================================================
-- Diagnose Stuck Processing Entry
-- ==============================================================================

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

-- Check how long the entry has been processing
SELECT 
  id,
  status,
  processed_at,
  NOW() - processed_at AS time_since_processed,
  EXTRACT(EPOCH FROM (NOW() - processed_at))::int AS seconds_ago,
  CASE 
    WHEN processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ Will be retried (stuck > 5 min)'
    ELSE '⏳ Still processing (will retry in ' || (300 - EXTRACT(EPOCH FROM (NOW() - processed_at))::int) || ' seconds)'
  END AS retry_status
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- The problem: Entry is stuck in 'processing' but net.http_post never created a request
-- This means either:
-- 1. net.http_post is failing silently
-- 2. The function is not reaching the net.http_post call
-- 3. The entry was marked processing but the function errored before calling net.http_post

-- Solution: Reset the entry to 'pending' so it gets processed again
-- But first, let's check if there are any errors or if app_config is missing

