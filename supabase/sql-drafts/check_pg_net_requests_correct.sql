-- ==============================================================================
-- Check pg_net Requests (Corrected - check table structure first)
-- ==============================================================================

-- Query 2 (Corrected): Check if pg_net is creating HTTP requests
-- First, let's see what columns actually exist
SELECT 
  column_name
FROM information_schema.columns
WHERE table_schema = 'net'
  AND table_name IN ('http_request_queue', 'http_request')
ORDER BY table_name, ordinal_position;

-- Then try to query the actual requests (adjust columns based on what exists)
-- Common column names: id, url, method, headers, body, created, status, response_status, etc.
SELECT 
  *
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY created DESC
LIMIT 10;

-- Alternative: Check net.http_request table if it exists
SELECT 
  *
FROM net.http_request
WHERE url LIKE '%quick-handler%'
ORDER BY created DESC
LIMIT 10;

