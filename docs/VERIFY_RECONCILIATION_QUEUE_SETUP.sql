-- Verification Queries for Reconciliation Queue Setup
-- Run these after applying all migrations

-- ==============================================================================
-- 1. Verify Table Exists
-- ==============================================================================
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'reconciliation_queue'
) AS table_exists;

-- Expected: true

-- ==============================================================================
-- 2. Verify Table Schema
-- ==============================================================================
SELECT 
  column_name, 
  data_type, 
  is_nullable, 
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'reconciliation_queue'
ORDER BY ordinal_position;

-- Expected: Should show all columns (id, user_id, week_start_date, etc.)

-- ==============================================================================
-- 3. Verify Indexes Exist
-- ==============================================================================
SELECT 
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'reconciliation_queue'
ORDER BY indexname;

-- Expected: Should show 3 indexes
-- - idx_reconciliation_queue_pending
-- - idx_reconciliation_queue_user_week
-- - idx_reconciliation_queue_unique_pending

-- ==============================================================================
-- 4. Verify RPC Function: process_reconciliation_queue
-- ==============================================================================
SELECT 
  routine_name,
  routine_type,
  data_type AS return_type
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name = 'process_reconciliation_queue';

-- Expected: 1 row with routine_name = 'process_reconciliation_queue'

-- ==============================================================================
-- 5. Verify RPC Function: rpc_sync_daily_usage Has Queue Logic
-- ==============================================================================
SELECT 
  CASE 
    WHEN routine_definition LIKE '%reconciliation_queue%' THEN '✅ Queue logic found'
    ELSE '❌ Queue logic missing'
  END AS queue_logic_status
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name = 'rpc_sync_daily_usage';

-- Expected: '✅ Queue logic found'

-- Also check for key variables
SELECT 
  CASE 
    WHEN routine_definition LIKE '%v_prev_needs_reconciliation%' THEN '✅ Variable found'
    ELSE '❌ Variable missing'
  END AS variable_status
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name = 'rpc_sync_daily_usage';

-- Expected: '✅ Variable found'

-- ==============================================================================
-- 6. Verify Cron Jobs
-- ==============================================================================
SELECT 
  jobid,
  jobname,
  schedule,
  command,
  active,
  database,
  username
FROM cron.job 
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')
ORDER BY jobname;

-- Expected: 2 rows
-- - process-reconciliation-queue-testing: schedule = '* * * * *'
-- - process-reconciliation-queue-normal: schedule = '*/10 * * * *'

-- ==============================================================================
-- 7. Quick Health Check (All in One)
-- ==============================================================================
SELECT 
  'Table exists' AS check_name,
  EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'reconciliation_queue'
  ) AS status
UNION ALL
SELECT 
  'Process function exists' AS check_name,
  EXISTS (
    SELECT FROM information_schema.routines
    WHERE routine_schema = 'public' 
    AND routine_name = 'process_reconciliation_queue'
  ) AS status
UNION ALL
SELECT 
  'Sync function has queue logic' AS check_name,
  EXISTS (
    SELECT FROM information_schema.routines
    WHERE routine_schema = 'public' 
    AND routine_name = 'rpc_sync_daily_usage'
    AND routine_definition LIKE '%reconciliation_queue%'
  ) AS status
UNION ALL
SELECT 
  'Cron jobs exist' AS check_name,
  (SELECT COUNT(*) FROM cron.job 
   WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal')) = 2 AS status;

-- Expected: All 4 rows should show status = true


