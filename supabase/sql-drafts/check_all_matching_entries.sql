-- ==============================================================================
-- Check All Entries That Match WHERE Clause
-- ==============================================================================

-- Check if there are multiple entries and which one would be processed first
SELECT 
  id,
  status,
  processed_at,
  created_at,
  retry_count,
  CASE 
    WHEN status = 'pending' THEN 0  -- Process pending first
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN 1  -- Then stuck processing
    ELSE 999
  END AS priority,
  CASE 
    WHEN status = 'pending' THEN '✅ Will be processed first'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ Will be retried (stuck)'
    ELSE '❌ Will NOT be processed'
  END AS will_be_processed
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes')
ORDER BY 
  CASE WHEN status = 'pending' THEN 0 ELSE 1 END,  -- Process pending first
  created_at ASC  -- Oldest first
LIMIT 10;

-- Check total count
SELECT 
  COUNT(*) AS total_matching,
  COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
  COUNT(*) FILTER (WHERE status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes') AS stuck_count
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes');

