-- Set up cron job to automatically check for expired grace periods and trigger settlement
-- This runs frequently to catch grace periods as soon as they expire
-- 
-- Schedule: Every minute (works for both testing mode with 1-minute grace periods 
-- and normal mode - though function exits early in normal mode)
--
-- Note: The function itself checks TESTING_MODE and adjusts behavior accordingly
-- In normal mode, the function exits immediately and doesn't interfere with production
--
-- IMPORTANT: Update the project URL below for your environment:
--   Staging: https://auqujbppoytkeqdsgrbl.supabase.co
--   Production: https://whdftvcrtrsnefhprebj.supabase.co
--
-- The service role key is read from app.settings.service_role_key
-- Set it using: ALTER DATABASE postgres SET app.settings.service_role_key = 'your-key-here';

-- Ensure required extensions are enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
-- Note: pg_net extension may need to be enabled separately via Supabase Dashboard
-- if you don't have superuser privileges. It's usually enabled by default in Supabase.
-- If net.http_post fails, enable pg_net via Dashboard: Database → Extensions → pg_net

-- Delete existing auto-settlement job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'auto-settlement-checker';

-- Schedule auto-settlement-checker to run every minute
-- This ensures we catch expired grace periods quickly (works for both testing and normal mode)
-- The function itself checks TESTING_MODE and only processes in testing mode
SELECT cron.schedule(
  'auto-settlement-checker',        -- Job name
  '* * * * *',                      -- Schedule: Every minute (cron format: minute hour day month weekday)
  $$SELECT
    net.http_post(
      url := 'https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/auto-settlement-checker',  -- ⚠️ UPDATE THIS for production
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
WHERE jobname = 'auto-settlement-checker';

