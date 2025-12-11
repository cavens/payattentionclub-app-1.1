-- Set up cron job to run weekly-close every Monday at 12:00 EST (17:00 UTC)
-- Note: Supabase uses UTC time, so 12:00 EST = 17:00 UTC (or 16:00 UTC during DST)

-- Ensure pg_cron extension is enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Delete existing weekly-close job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE command LIKE '%weekly-close%';

-- Schedule weekly-close to run every Monday at 17:00 UTC (12:00 EST)
-- Cron format: minute hour day-of-month month day-of-week
-- 0 17 * * 1 = Every Monday at 17:00 UTC
SELECT cron.schedule(
  'weekly-close-monday',           -- Job name
  '0 17 * * 1',                    -- Schedule: Every Monday at 17:00 UTC (12:00 EST)
  $$SELECT
    net.http_post(
      url := 'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);

-- Verify the job was created
SELECT 
  jobid,
  schedule,
  command,
  active
FROM cron.job
WHERE jobname = 'weekly-close-monday';




