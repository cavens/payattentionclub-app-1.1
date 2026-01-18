-- ==============================================================================
-- Test Reconciliation Flow (After Stripe Secret Fix)
-- ==============================================================================
-- This tests the complete reconciliation flow:
-- 1. Check if there's a pending queue entry
-- 2. Manually trigger process_reconciliation_queue()
-- 3. Check the results
-- ==============================================================================

-- Step 1: Check for pending queue entries
SELECT 
  'Step 1: Pending Queue Entries' AS step,
  id,
  user_id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  created_at,
  processed_at
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes')
ORDER BY created_at ASC
LIMIT 5;

-- Step 2: Manually trigger the function (this will show debug output)
DO $$
DECLARE
  v_notice text;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Testing process_reconciliation_queue()...';
  RAISE NOTICE '========================================';
  
  PERFORM public.process_reconciliation_queue();
  
  RAISE NOTICE '✅ Function completed without exceptions';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed: %', SQLERRM;
    RAISE NOTICE 'Error state: %', SQLSTATE;
END $$;

-- Step 3: Check queue entry status after processing
SELECT 
  'Step 3: Queue Entry Status After Processing' AS step,
  id,
  user_id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  retry_count,
  error_message,
  created_at,
  processed_at,
  CASE 
    WHEN status = 'completed' THEN '✅ Successfully completed'
    WHEN status = 'processing' THEN '🔄 Still processing (check again in a moment)'
    WHEN status = 'failed' THEN '❌ Failed: ' || COALESCE(error_message, 'Unknown error')
    WHEN status = 'pending' THEN '⏳ Still pending (may not have matched WHERE clause)'
    ELSE '❓ Status: ' || status
  END AS result
FROM reconciliation_queue
WHERE status IN ('pending', 'processing', 'completed', 'failed')
ORDER BY processed_at DESC NULLS LAST, created_at DESC
LIMIT 5;

-- Step 4: Check pg_net requests to quick-handler (should show recent calls)
-- First check the request queue
SELECT 
  'Step 4a: Recent quick-handler Requests' AS step,
  id,
  url,
  method,
  'Request queued' AS result
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
ORDER BY id DESC
LIMIT 5;

-- Then check the responses (check what columns exist first)
-- Note: Column names may vary, so we'll select what we can
SELECT 
  'Step 4b: Recent quick-handler Responses' AS step,
  id,
  status_code,
  LEFT(content, 200) AS content_preview,
  CASE 
    WHEN status_code = 200 THEN '✅ Success'
    WHEN status_code >= 400 THEN '❌ Error: ' || status_code
    WHEN status_code IS NULL THEN '⏳ Pending'
    ELSE '❓ Status: ' || status_code
  END AS result
FROM net._http_response
WHERE (content LIKE '%refundsIssued%' OR content LIKE '%chargesIssued%' OR content LIKE '%stripe is not defined%' OR content LIKE '%Stripe credentials missing%')
ORDER BY id DESC
LIMIT 5;

-- Step 5: Check if reconciliation was actually processed
SELECT 
  'Step 5: Reconciliation Status' AS step,
  user_id,
  week_start_date,
  needs_reconciliation,
  reconciliation_delta_cents,
  refund_amount_cents,
  charged_amount_cents,
  actual_amount_cents,
  settlement_status,
  CASE 
    WHEN needs_reconciliation = false AND refund_amount_cents > 0 THEN '✅ Refund issued'
    WHEN needs_reconciliation = false AND reconciliation_delta_cents = 0 THEN '✅ Reconciliation complete (no action needed)'
    WHEN needs_reconciliation = true THEN '⏳ Still needs reconciliation'
    ELSE '❓ Status unclear'
  END AS result
FROM user_week_penalties
WHERE needs_reconciliation = true
   OR refund_amount_cents > 0
ORDER BY reconciliation_detected_at DESC NULLS LAST
LIMIT 5;

