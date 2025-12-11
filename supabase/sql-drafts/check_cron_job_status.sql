-- Check if the cron job exists and is active

SELECT 
  jobid,
  schedule,
  command,
  nodename,
  nodeport,
  database,
  username,
  active,
  jobname
FROM cron.job
WHERE jobname = 'pac_weekly_close_job';

-- If no rows returned, the cron job doesn't exist
-- If active = false, the cron job exists but is disabled
-- If active = true, the cron job exists and is enabled




