-- ==============================================================================
-- Check Why Reconciliation Didn't Complete
-- ==============================================================================

-- 1. Queue entry status
SELECT 
  'Queue Entry' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at,
  created_at,
  CASE 
    WHEN status = 'completed' THEN '✅ Completed (but reconciliation still needed - check quick-handler response)'
    WHEN status = 'processing' THEN '🔄 Still processing'
    WHEN status = 'pending' THEN '⏳ Still pending (function may not have found it)'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown')
    ELSE '❓ ' || status
  END AS result
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18'
ORDER BY created_at DESC
LIMIT 1;

-- 2. Most recent quick-handler response
SELECT 
  'Most Recent Response' AS check_type,
  id,
  status_code,
  content,
  CASE 
    WHEN status_code = 200 AND content LIKE '%"refundsIssued":1%' THEN '✅ Refund issued successfully'
    WHEN status_code = 200 AND content LIKE '%"refundsIssued":0%' THEN '⚠️ Processed but no refund issued (check details)'
    WHEN status_code = 200 AND content LIKE '%"processed":0%' THEN '⚠️ Processed 0 items (check failures)'
    WHEN status_code = 200 AND content LIKE '%"failures"%' THEN '❌ Had failures: ' || content
    WHEN status_code = 401 THEN '❌ Unauthorized (function may be private)'
    WHEN status_code >= 400 THEN '❌ Error: ' || status_code || ' - ' || LEFT(content, 100)
    WHEN status_code IS NULL THEN '⏳ Pending'
    ELSE '❓ Status: ' || COALESCE(status_code::text, 'NULL') || ' - ' || LEFT(content, 100)
  END AS result
FROM net._http_response
WHERE content LIKE '%refundsIssued%' 
   OR content LIKE '%chargesIssued%'
   OR content LIKE '%processed%'
   OR content LIKE '%failures%'
   OR content LIKE '%Unauthorized%'
ORDER BY id DESC
LIMIT 1;

-- 3. Check if there are any recent requests to quick-handler
SELECT 
  'Recent Requests' AS check_type,
  id,
  url,
  method,
  LEFT(body::text, 200) AS body_preview
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY id DESC
LIMIT 3;

