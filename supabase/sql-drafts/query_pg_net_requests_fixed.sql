-- ==============================================================================
-- Query 2 (Fixed): Check if pg_net is creating HTTP requests
-- ==============================================================================

-- Check if any requests to quick-handler were created
SELECT 
  id,
  method,
  url,
  headers,
  body,
  timeout_milliseconds,
  CASE 
    WHEN url LIKE '%quick-handler%' THEN '✅ Found request to quick-handler'
    ELSE 'Other URL'
  END AS status
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY id DESC
LIMIT 10;

-- Also check total count
SELECT 
  'Summary' AS check_type,
  COUNT(*) AS total_requests,
  COUNT(*) FILTER (WHERE url LIKE '%quick-handler%') AS quick_handler_requests,
  CASE 
    WHEN COUNT(*) FILTER (WHERE url LIKE '%quick-handler%') > 0 THEN '✅ Requests found'
    ELSE '❌ No requests to quick-handler found'
  END AS status
FROM net.http_request_queue;

-- Compare with bright-service (settlement) to see if that's working
SELECT 
  'Comparison' AS check_type,
  url,
  COUNT(*) AS request_count,
  CASE 
    WHEN url LIKE '%bright-service%' THEN '✅ Settlement requests found'
    WHEN url LIKE '%quick-handler%' THEN '✅ Reconciliation requests found'
    ELSE 'Other'
  END AS status
FROM net.http_request_queue
WHERE url LIKE '%bright-service%' OR url LIKE '%quick-handler%'
GROUP BY url
ORDER BY request_count DESC;

