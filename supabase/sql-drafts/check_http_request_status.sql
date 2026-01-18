-- ==============================================================================
-- Check HTTP Request Status from pg_net
-- ==============================================================================
-- This checks if the HTTP request from process_reconciliation_queue actually succeeded
-- ==============================================================================

-- Check recent HTTP requests made by process_reconciliation_queue
-- The request_id from net.http_post() can be used to check status
SELECT 
  id,
  url,
  method,
  headers,
  body,
  status_code,
  content,
  error_msg,
  created,
  updated
FROM net.http_request
WHERE url LIKE '%quick-handler%'
ORDER BY created DESC
LIMIT 10;

-- If you have the specific request_id from the queue processing logs,
-- you can check that specific request:
-- SELECT * FROM net.http_request WHERE id = <request_id>;

-- Note: net.http_post() is asynchronous, so the request might still be pending
-- Check the 'status_code' field - it will be NULL if still pending


