-- ==============================================================================
-- Reset Entry and Test Again
-- ==============================================================================

-- Step 1: Check app_config first
SELECT 
  key,
  CASE 
    WHEN value IS NULL THEN '❌ NULL - Function will return early!'
    WHEN LENGTH(value) = 0 THEN '❌ Empty - Function will return early!'
    WHEN key IN ('service_role_key', 'reconciliation_secret') THEN '✅ Set (' || LENGTH(value) || ' chars)'
    ELSE '✅ ' || value
  END AS value_status
FROM app_config
WHERE key IN ('service_role_key', 'supabase_url', 'reconciliation_secret', 'testing_mode')
ORDER BY key;

-- Step 2: Reset the stuck entry to 'pending'
UPDATE reconciliation_queue
SET 
  status = 'pending',
  processed_at = NULL,
  error_message = NULL
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Step 3: Verify it's reset
SELECT 
  id,
  status,
  processed_at,
  CASE 
    WHEN status = 'pending' THEN '✅ Reset - Will be processed on next cron run'
    ELSE '❌ Still ' || status
  END AS status_display
FROM reconciliation_queue
WHERE id = '74ca2550-b3c4-4518-b6d5-6a9a6168fbb0';

-- Step 4: Wait 1-2 minutes for cron to run, then check:
-- - Did the entry get processed?
-- - Did net.http_post create a request?
-- - Did quick-handler get called?

