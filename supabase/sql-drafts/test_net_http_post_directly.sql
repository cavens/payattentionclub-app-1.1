-- ==============================================================================
-- Test net.http_post Directly
-- ==============================================================================
-- This will tell us if net.http_post works at all
-- ==============================================================================

-- Test 1: Simple test call (like settlement does)
DO $$
DECLARE
  v_request_id bigint;
  v_supabase_url text;
BEGIN
  -- Get supabase_url
  SELECT value INTO v_supabase_url
  FROM app_config
  WHERE key = 'supabase_url';
  
  IF v_supabase_url IS NULL THEN
    RAISE NOTICE '❌ supabase_url not set';
    RETURN;
  END IF;
  
  RAISE NOTICE 'Testing net.http_post with URL: %', v_supabase_url || '/functions/v1/quick-handler';
  
  -- Try calling net.http_post directly
  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/quick-handler',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-reconciliation-secret', 'test'
    ),
    body := jsonb_build_object('userId', 'test')
  ) INTO v_request_id;
  
  RAISE NOTICE '✅ net.http_post returned request_id: %', v_request_id;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ net.http_post failed: %', SQLERRM;
    RAISE NOTICE 'Error state: %', SQLSTATE;
END $$;

-- Check if request was created
SELECT 
  'Request Check' AS check_type,
  COUNT(*) AS request_count,
  CASE 
    WHEN COUNT(*) > 0 THEN '✅ Request created!'
    ELSE '❌ No request created'
  END AS status
FROM net.http_request_queue
WHERE url LIKE '%quick-handler%'
  AND created > NOW() - INTERVAL '1 minute';

