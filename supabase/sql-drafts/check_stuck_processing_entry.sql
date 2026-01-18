-- ==============================================================================
-- Check Why Queue Entry Is Stuck in Processing
-- ==============================================================================

-- 1. Check the queue entry details
SELECT 
  'Queue Entry Details' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at,
  created_at,
  NOW() - processed_at AS time_since_processed,
  CASE 
    WHEN processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ Should be retried (> 5 min)'
    ELSE '⏳ Not yet eligible for retry (< 5 min)'
  END AS retry_eligibility
FROM reconciliation_queue
WHERE id = '7b528a6a-50e7-476d-a264-f3f835632d52';

-- 2. Check if it matches the WHERE clause in process_reconciliation_queue
SELECT 
  'WHERE Clause Match' AS check_type,
  id,
  status,
  processed_at,
  CASE 
    WHEN status = 'pending' THEN '✅ Matches (pending)'
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '✅ Matches (stuck processing)'
    ELSE '❌ Does NOT match WHERE clause'
  END AS matches_where_clause,
  NOW() - processed_at AS time_elapsed
FROM reconciliation_queue
WHERE id = '7b528a6a-50e7-476d-a264-f3f835632d52';

-- 3. Check recent quick-handler responses (look for this user or this delta amount)
SELECT 
  'Recent quick-handler Responses' AS check_type,
  id,
  status_code,
  LEFT(content, 400) AS content_preview,
  CASE 
    WHEN content LIKE '%14a914ef-e323-4e0e-8701-8e008422f927%' THEN '✅ This user'
    WHEN content LIKE '%refundsIssued%' AND content LIKE '%348%' THEN '✅ Likely this refund (348 cents)'
    WHEN status_code = 200 AND content LIKE '%refundsIssued%' THEN '✅ Success - refund issued'
    WHEN status_code >= 400 THEN '❌ Error: ' || status_code
    ELSE 'Other'
  END AS result
FROM net._http_response
WHERE created > NOW() - INTERVAL '20 minutes'
ORDER BY id DESC
LIMIT 10;

-- 4. Manually trigger process_reconciliation_queue to see what happens
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Manually triggering process_reconciliation_queue()...';
  RAISE NOTICE '========================================';
  
  PERFORM public.process_reconciliation_queue();
  
  RAISE NOTICE '✅ Function completed';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed: %', SQLERRM;
END $$;

-- 5. Check queue entry status after manual trigger
SELECT 
  'Queue Entry After Manual Trigger' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at
FROM reconciliation_queue
WHERE id = '7b528a6a-50e7-476d-a264-f3f835632d52';

