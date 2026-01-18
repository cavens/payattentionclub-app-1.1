-- ==============================================================================
-- Check What quick-handler Returned for This User
-- ==============================================================================

-- Check all recent quick-handler responses
SELECT 
  'All Recent Responses' AS check_type,
  id,
  status_code,
  content
FROM net._http_response
WHERE content LIKE '%refundsIssued%'
   OR content LIKE '%chargesIssued%'
   OR content LIKE '%processed%'
   OR content LIKE '%failures%'
   OR content LIKE '%14a914ef-e323-4e0e-8701-8e008422f927%'
ORDER BY id DESC
LIMIT 10;

-- Check recent requests to quick-handler
SELECT 
  'Recent Requests' AS check_type,
  id,
  url,
  method,
  LEFT(body::text, 200) AS body_preview
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY id DESC
LIMIT 5;

