-- Verify cron job setup for weekly-close

-- 1) Check if cron job exists
SELECT 
  jobid,
  schedule,
  command,
  nodename,
  nodeport,
  database,
  username,
  active
FROM cron.job
WHERE jobname = 'pac_weekly_close_job';

-- 2) Check if call_weekly_close function exists and what it does
SELECT 
  routine_name,
  routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'call_weekly_close';

-- 3) Show the actual function code
SELECT pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'call_weekly_close'
  AND pronamespace = 'public'::regnamespace;


