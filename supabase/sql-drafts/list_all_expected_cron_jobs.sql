-- ==============================================================================
-- List All Expected Cron Jobs
-- ==============================================================================
-- This shows what cron jobs SHOULD exist based on migrations
-- ==============================================================================

-- Expected cron jobs:

-- 1. RECONCILIATION (from 20260111220100_setup_reconciliation_queue_cron.sql):
--    - process-reconciliation-queue-testing (every 1 minute)
--    - process-reconciliation-queue-normal (every 10 minutes)

-- 2. SETTLEMENT:
--    - run-settlement-testing (from 20260117180000_setup_settlement_cron_testing_mode.sql)
--      * Every 2 minutes
--      * Calls: public.call_settlement()
--      * call_settlement() checks testing_mode and only runs if true
--
--    - Weekly-Settlement (from 20260118210000_fix_weekly_settlement_cron.sql)
--      * Tuesday 12:00 (0 12 * * 2)
--      * Calls: public.call_settlement_normal()
--      * call_settlement_normal() does NOT check testing_mode

-- ==============================================================================
-- Check what actually exists:
-- ==============================================================================

SELECT 
  jobid,
  jobname,
  schedule,
  active,
  LEFT(command, 100) as command_preview
FROM cron.job 
ORDER BY jobname;

-- ==============================================================================
-- Summary of expected vs actual:
-- ==============================================================================

SELECT 
  CASE 
    WHEN jobname = 'process-reconciliation-queue-testing' THEN '✅ Expected'
    WHEN jobname = 'process-reconciliation-queue-normal' THEN '✅ Expected'
    WHEN jobname = 'run-settlement-testing' THEN '⚠️  Exists but validation expects "Testing-Settlement"'
    WHEN jobname = 'Testing-Settlement' THEN '✅ Expected by validation function'
    WHEN jobname = 'Weekly-Settlement' THEN '✅ Expected'
    ELSE '❓ Unexpected'
  END as status,
  jobname,
  active,
  schedule
FROM cron.job
ORDER BY jobname;

