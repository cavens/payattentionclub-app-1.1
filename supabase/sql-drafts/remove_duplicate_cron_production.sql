-- ==============================================================================
-- Remove Duplicate Weekly Close Cron Job in Production
-- ==============================================================================
-- Removes the old 'pac_weekly_close_job' since we have 'weekly-close-production'
-- Run this in Production SQL Editor
-- ==============================================================================

-- Remove the old duplicate job
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'pac_weekly_close_job';

-- Verify remaining jobs
SELECT 
    jobid,
    jobname,
    schedule,
    active
FROM cron.job
WHERE jobname LIKE '%weekly%close%'
ORDER BY jobid;


