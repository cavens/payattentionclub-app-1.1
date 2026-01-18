-- ==============================================================================
-- Check If Entries Match WHERE Clause
-- ==============================================================================

-- Check if the entry matches the WHERE clause in the function
SELECT 
  'Entry Status Check' AS check_type,
  id,
  status,
  processed_at,
  NOW() - processed_at AS time_since_processed,
  EXTRACT(EPOCH FROM (NOW() - processed_at))::int AS seconds_ago,
  CASE 
    WHEN status = 'pending' THEN '✅ MATCHES WHERE clause (status = pending)'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ MATCHES WHERE clause (stuck > 5 min)'
    WHEN status = 'processing' THEN '❌ Does NOT match (processing but < 5 min ago)'
    ELSE '❌ Does NOT match (status = ' || status || ')'
  END AS matches_where_clause
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Check if ANY entries match the WHERE clause
SELECT 
  'Entries Matching WHERE' AS check_type,
  COUNT(*) AS matching_count,
  COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
  COUNT(*) FILTER (WHERE status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes') AS stuck_count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Found ' || COUNT(*) || ' entries to process'
    ELSE '❌ No entries match WHERE clause - Function loop will NOT execute!'
  END AS status
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes');

-- The issue: If the entry is in 'processing' but was processed less than 5 minutes ago,
-- it won't match the WHERE clause, so the function loop won't execute.
-- Solution: Reset the entry to 'pending' OR wait 5+ minutes for it to be retried

