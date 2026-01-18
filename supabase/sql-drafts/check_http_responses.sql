-- ==============================================================================
-- Check HTTP Responses for Reconciliation Requests
-- ==============================================================================

-- First, check the structure of _http_response table
SELECT 
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'net'
  AND table_name = '_http_response'
ORDER BY ordinal_position;

-- Then check recent responses (adjust columns based on what exists)
SELECT 
  *
FROM net._http_response
ORDER BY created DESC
LIMIT 10;

-- Check specifically for quick-handler requests
-- (adjust URL column name based on table structure)
SELECT 
  *
FROM net._http_response
WHERE url LIKE '%quick-handler%'
ORDER BY created DESC
LIMIT 10;

-- Compare with bright-service (settlement) requests
SELECT 
  *
FROM net._http_response
WHERE url LIKE '%bright-service%'
ORDER BY created DESC
LIMIT 5;

