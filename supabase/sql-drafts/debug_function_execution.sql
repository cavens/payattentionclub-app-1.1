-- ==============================================================================
-- Debug Function Execution
-- ==============================================================================

-- Check 1: Queue entry status (is it being processed?)
SELECT 
  id,
  status,
  processed_at,
  error_message,
  retry_count,
  CASE 
    WHEN status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes' THEN '⚠️ Stuck processing (should retry)'
    WHEN status = 'processing' THEN '🔄 Currently processing'
    WHEN status = 'pending' THEN '⏳ Pending'
    WHEN status = 'completed' THEN '✅ Completed'
    WHEN status = 'failed' THEN '❌ Failed'
    ELSE '❓ ' || status
  END AS status_display
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Check 2: Are there ANY pending entries?
SELECT 
  COUNT(*) AS pending_count,
  COUNT(*) FILTER (WHERE status = 'pending') AS pending,
  COUNT(*) FILTER (WHERE status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes') AS stuck_processing
FROM reconciliation_queue
WHERE status = 'pending'
   OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes');

-- Check 3: Manually test the function with detailed error checking
DO $$
DECLARE
  v_notice text;
BEGIN
  -- Enable notice output
  RAISE NOTICE 'Starting manual function test...';
  
  PERFORM public.process_reconciliation_queue();
  
  RAISE NOTICE '✅ Function completed without exceptions';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ Function failed with exception: %', SQLERRM;
    RAISE NOTICE 'Error state: %', SQLSTATE;
    RAISE NOTICE 'Error detail: %', SQLERRM;
END $$;

-- Check 4: Verify app_config values are still set
SELECT 
  key,
  CASE 
    WHEN value IS NULL THEN '❌ NULL'
    WHEN LENGTH(value) = 0 THEN '❌ Empty'
    ELSE '✅ Set'
  END AS status
FROM app_config
WHERE key IN ('service_role_key', 'supabase_url', 'reconciliation_secret');

