-- ==============================================================================
-- Check Quick-Handler Responses
-- ==============================================================================

-- Check if there are any quick-handler responses
-- Note: The _http_response table doesn't have a URL column, so we need to check
-- the content or check the request queue to see which URLs were called

-- First, let's check the request queue to see if quick-handler requests exist
SELECT 
  'Request Queue' AS check_type,
  id,
  url,
  method,
  headers,
  body
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY id DESC
LIMIT 10;

-- Check recent responses that might be from quick-handler
-- (quick-handler returns JSON with summary, refundsIssued, chargesIssued, etc.)
SELECT 
  'Recent Responses' AS check_type,
  id,
  status_code,
  content,
  created,
  CASE 
    WHEN content LIKE '%refundsIssued%' OR content LIKE '%chargesIssued%' THEN '✅ Likely quick-handler response'
    WHEN content LIKE '%weekEndDate%' THEN 'Settlement response'
    WHEN content LIKE '%testing_mode%' THEN 'Settlement checker response'
    WHEN status_code = 401 THEN '❌ Authentication error'
    ELSE 'Other'
  END AS response_type
FROM net._http_response
WHERE created > NOW() - INTERVAL '10 minutes'
ORDER BY created DESC
LIMIT 20;

-- Check queue entry status
SELECT 
  'Queue Entry' AS check_type,
  id,
  status,
  processed_at,
  error_message,
  CASE 
    WHEN status = 'completed' THEN '✅ Completed'
    WHEN status = 'processing' THEN '🔄 Processing'
    WHEN status = 'pending' THEN '⏳ Pending'
    WHEN status = 'failed' THEN '❌ Failed'
    ELSE '❓ ' || status
  END AS status_display
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

