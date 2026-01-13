-- ==============================================================================
-- Fix Reconciliation Queue Cron Jobs (with error checking)
-- Run this in Supabase Dashboard → SQL Editor
-- ==============================================================================

-- Step 1: Check if pg_cron extension is enabled
SELECT 
  extname,
  extversion,
  n.nspname as schema_name
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE extname = 'pg_cron';

-- Step 2: See ALL existing cron jobs
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  LEFT(command, 100) as command_preview
FROM cron.job
ORDER BY jobid;

-- Step 3: Delete any existing reconciliation queue jobs
DO $$
DECLARE
  deleted_count integer := 0;
BEGIN
  SELECT COUNT(*) INTO deleted_count
  FROM cron.job 
  WHERE command LIKE '%process_reconciliation_queue%';
  
  RAISE NOTICE 'Found % existing reconciliation queue jobs to delete', deleted_count;
  
  PERFORM cron.unschedule(jobid) 
  FROM cron.job 
  WHERE command LIKE '%process_reconciliation_queue%';
  
  RAISE NOTICE 'Deleted existing reconciliation queue jobs';
END;
$$;

-- Step 4: Create testing mode cron job (runs every 1 minute)
-- cron.schedule() returns a jobid directly, so we call it and check the result
DO $$
DECLARE
  testing_job_id bigint;
BEGIN
  testing_job_id := cron.schedule(
    'process-reconciliation-queue-testing',
    '* * * * *',
    'SELECT public.process_reconciliation_queue()'
  );
  
  IF testing_job_id IS NULL THEN
    RAISE EXCEPTION 'Failed to create testing mode cron job';
  END IF;
  
  RAISE NOTICE '✅ Created testing mode cron job with ID: %', testing_job_id;
END;
$$;

-- Step 5: Create normal mode cron job (runs every 10 minutes)
DO $$
DECLARE
  normal_job_id bigint;
BEGIN
  normal_job_id := cron.schedule(
    'process-reconciliation-queue-normal',
    '*/10 * * * *',
    'SELECT public.process_reconciliation_queue()'
  );
  
  IF normal_job_id IS NULL THEN
    RAISE EXCEPTION 'Failed to create normal mode cron job';
  END IF;
  
  RAISE NOTICE '✅ Created normal mode cron job with ID: %', normal_job_id;
END;
$$;

-- Step 6: Verify both jobs were created
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  LEFT(command, 80) as command_preview
FROM cron.job
WHERE command LIKE '%process_reconciliation_queue%'
ORDER BY jobname;

-- If you see 2 rows above, the jobs were created successfully!
-- To view them in the Dashboard: Database → Extensions → pg_cron → Jobs

