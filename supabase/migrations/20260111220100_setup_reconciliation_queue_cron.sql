-- ==============================================================================
-- Migration: Set up cron jobs to process reconciliation queue
-- Date: 2026-01-11
-- Purpose: Automatically process reconciliation requests queued by rpc_sync_daily_usage
-- ==============================================================================
-- 
-- Two cron jobs with different schedules:
-- - Testing mode: Every 1 minute (fast processing for testing)
-- - Normal mode: Every 10 minutes (efficient for production)
-- 
-- The function checks TESTING_MODE from app_config and only processes if it matches.
-- Both cron jobs can run, but only one will do work based on TESTING_MODE setting.
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

-- Add comment
COMMENT ON FUNCTION public.process_reconciliation_queue() IS 
'Processes pending reconciliation requests from reconciliation_queue table.
Called by pg_cron with different schedules based on mode:
- Testing mode: Every 1 minute (job: process-reconciliation-queue-testing)
- Normal mode: Every 10 minutes (job: process-reconciliation-queue-normal)
Function checks TESTING_MODE from app_config and only processes if it matches.
Uses pg_net.http_post() to call quick-handler Edge Function.';


