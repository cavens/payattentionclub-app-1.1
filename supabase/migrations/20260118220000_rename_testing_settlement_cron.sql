-- ==============================================================================
-- Migration: Rename testing settlement cron job to match validation function
-- Date: 2026-01-18
-- Purpose: Rename 'run-settlement-testing' to 'Testing-Settlement' for consistency
-- ==============================================================================
-- 
-- ISSUE:
-- The validation function (rpc_validate_mode_consistency) expects a cron job
-- named 'Testing-Settlement', but migration 20260117180000 created it as 'run-settlement-testing'.
-- 
-- FIX:
-- Rename 'run-settlement-testing' to 'Testing-Settlement' to match:
-- 1. The validation function's expectation
-- 2. The naming pattern of 'Weekly-Settlement' (more user-friendly)
-- 
-- This ensures consistency across the codebase.
-- ==============================================================================

-- Find and rename the testing settlement cron job
DO $rename$
DECLARE
  old_job_id bigint;
  new_job_id bigint;
  old_jobname text := 'run-settlement-testing';
  new_jobname text := 'Testing-Settlement';
BEGIN
  -- Find the job ID
  SELECT jobid INTO old_job_id
  FROM cron.job
  WHERE jobname = old_jobname
  LIMIT 1;
  
  -- If the job exists, unschedule it
  IF old_job_id IS NOT NULL THEN
    -- Unschedule the old job
    PERFORM cron.unschedule(old_job_id);
    RAISE NOTICE 'Unscheduled old cron job: %', old_jobname;
  END IF;
  
  -- Check if new job already exists (shouldn't, but just in case)
  SELECT jobid INTO new_job_id
  FROM cron.job
  WHERE jobname = new_jobname
  LIMIT 1;
  
  -- Create the new job if it doesn't exist
  IF new_job_id IS NULL THEN
    SELECT cron.schedule(
      new_jobname,  -- Job name
      '*/2 * * * *',  -- Every 2 minutes
      'SELECT public.call_settlement()'  -- Use regular string instead of dollar-quoted
    ) INTO new_job_id;
    
    IF old_job_id IS NOT NULL THEN
      RAISE NOTICE 'Renamed cron job from % to % (jobid: %)', old_jobname, new_jobname, new_job_id;
    ELSE
      RAISE NOTICE 'Created cron job % (jobid: %)', new_jobname, new_job_id;
    END IF;
  ELSE
    RAISE NOTICE 'Cron job % already exists (jobid: %)', new_jobname, new_job_id;
  END IF;
END $rename$;

-- Verify the cron job exists with the correct name
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
WHERE jobname = 'Testing-Settlement';

