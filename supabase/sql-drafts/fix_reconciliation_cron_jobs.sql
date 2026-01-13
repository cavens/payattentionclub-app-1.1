-- ==============================================================================
-- Fix Reconciliation Queue Cron Jobs
-- Run this in Supabase Dashboard → SQL Editor
-- ==============================================================================

-- Step 1: See ALL existing cron jobs
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  LEFT(command, 100) as command_preview
FROM cron.job
ORDER BY jobid;

-- Step 2: Delete any existing reconciliation queue jobs
-- (Delete by command content, not just name, to catch all variations)
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE command LIKE '%process_reconciliation_queue%';

-- Step 3: Create testing mode cron job (runs every 1 minute)
SELECT cron.schedule(
  'process-reconciliation-queue-testing',
  '* * * * *',
  $$SELECT public.process_reconciliation_queue()$$
) as testing_job_id;

-- Step 4: Create normal mode cron job (runs every 10 minutes)
SELECT cron.schedule(
  'process-reconciliation-queue-normal',
  '*/10 * * * *',
  $$SELECT public.process_reconciliation_queue()$$
) as normal_job_id;

-- Step 5: Verify both jobs were created
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  LEFT(command, 80) as command_preview
FROM cron.job
WHERE command LIKE '%process_reconciliation_queue%'
ORDER BY jobname;



