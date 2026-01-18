-- ==============================================================================
-- Setup Reconciliation Queue Cron Job
-- ==============================================================================
-- Run this in Supabase SQL Editor to set up the cron jobs
-- This is the same as the migration file, but can be run directly
-- ==============================================================================

-- Ensure required extensions are enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Delete existing reconciliation queue processor jobs if they exist
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal');

-- Schedule reconciliation queue processor for TESTING MODE (every 1 minute)
-- This ensures reconciliation requests are processed quickly during testing
SELECT cron.schedule(
  'process-reconciliation-queue-testing',  -- Job name
  '* * * * *',                              -- Every minute
  $$SELECT public.process_reconciliation_queue()$$
);

-- Schedule reconciliation queue processor for NORMAL MODE (every 10 minutes)
-- More efficient for production where reconciliation is less frequent
SELECT cron.schedule(
  'process-reconciliation-queue-normal',   -- Job name
  '*/10 * * * *',                          -- Every 10 minutes
  $$SELECT public.process_reconciliation_queue()$$
);

-- Verify the cron jobs were created
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
WHERE jobname LIKE '%reconciliation%'
ORDER BY jobname;

