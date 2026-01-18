-- ==============================================================================
-- Test Reconciliation After Making quick-handler Public
-- ==============================================================================

-- Step 1: Reset the queue entry to pending (so we can test again)
-- This will reset regardless of current status (pending, processing, completed, failed)
UPDATE reconciliation_queue
SET status = 'pending',
    processed_at = NULL,
    error_message = NULL,
    retry_count = 0
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- Step 2: Check queue entry is now pending
SELECT 
  'Queue Entry Status' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  CASE 
    WHEN status = 'pending' THEN '✅ Ready to process'
    ELSE '❓ Status: ' || status
  END AS result
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- Step 3: Manually trigger the function
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Triggering process_reconciliation_queue()...';
  RAISE NOTICE '========================================';
  
  PERFORM public.process_reconciliation_queue();
  
  RAISE NOTICE '✅ Function completed';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed: %', SQLERRM;
END $$;

-- Step 4: Check queue entry status after processing
SELECT 
  'Queue Entry After Processing' AS check_type,
  id,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  processed_at,
  CASE 
    WHEN status = 'completed' THEN '✅ Successfully completed'
    WHEN status = 'processing' THEN '🔄 Processing (may complete shortly)'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown error')
    WHEN status = 'pending' THEN '⏳ Still pending (may not have matched WHERE clause)'
    ELSE '❓ Status: ' || status
  END AS result
FROM reconciliation_queue
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

-- Step 5: Check recent quick-handler responses
SELECT 
  'Recent quick-handler Response' AS check_type,
  id,
  status_code,
  LEFT(content, 400) AS content_preview,
  CASE 
    WHEN status_code = 200 AND content LIKE '%refundsIssued%' THEN '✅ Success - Refund issued'
    WHEN status_code = 200 AND content LIKE '%processed%' THEN '✅ Success - Processed'
    WHEN status_code = 200 AND content LIKE '%stripe is not defined%' THEN '❌ Stripe not initialized'
    WHEN status_code = 200 AND content LIKE '%Stripe credentials missing%' THEN '❌ Missing Stripe secret'
    WHEN status_code = 401 THEN '❌ Authentication error (function may be private)'
    WHEN status_code >= 400 THEN '❌ Error: ' || status_code
    WHEN status_code IS NULL THEN '⏳ Pending'
    ELSE '❓ Status: ' || COALESCE(status_code::text, 'NULL')
  END AS result
FROM net._http_response
WHERE content LIKE '%refundsIssued%' 
   OR content LIKE '%chargesIssued%'
   OR content LIKE '%processed%'
   OR content LIKE '%stripe%'
   OR content LIKE '%Unauthorized%'
ORDER BY id DESC
LIMIT 3;

-- Step 6: Check if reconciliation was actually processed
SELECT 
  'Reconciliation Status' AS check_type,
  needs_reconciliation,
  reconciliation_delta_cents,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents,
  CASE 
    WHEN needs_reconciliation = false AND refund_amount_cents > 0 THEN '✅ Refund issued: ' || refund_amount_cents || ' cents'
    WHEN needs_reconciliation = false THEN '✅ Reconciliation complete'
    WHEN needs_reconciliation = true AND reconciliation_delta_cents < 0 THEN '⏳ Needs refund: ' || ABS(reconciliation_delta_cents) || ' cents'
    WHEN needs_reconciliation = true AND reconciliation_delta_cents > 0 THEN '⏳ Needs charge: ' || reconciliation_delta_cents || ' cents'
    ELSE '❓ Status unclear'
  END AS result
FROM user_week_penalties
WHERE user_id = 'eef7f292-2892-4e65-bf13-376e77cb568b'
  AND week_start_date = '2026-01-18';

