-- Check if cron job for weekly-close exists

-- 1) Check if pg_cron extension is enabled
SELECT * FROM pg_extension WHERE extname = 'pg_cron';

-- 2) Check existing cron jobs
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
ORDER BY jobid;

-- 3) Check if weekly-close job exists
SELECT 
  jobid,
  schedule,
  command
FROM cron.job
WHERE command LIKE '%weekly-close%';


