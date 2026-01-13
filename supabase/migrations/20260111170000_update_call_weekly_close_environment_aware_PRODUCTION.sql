-- ==============================================================================
-- Production Setup: Update call_weekly_close() and Configure app.settings
-- ==============================================================================
-- 
-- This script:
-- 1. Updates call_weekly_close() to be environment-aware (calls bright-service)
-- 2. Sets app.settings.service_role_key (production secret key)
-- 3. Sets app.settings.supabase_url (production URL)
-- 4. Sets up the cron job for production
--
-- ⚠️  IMPORTANT: Replace the placeholder values below with your production values:
--    - YOUR_PRODUCTION_SERVICE_ROLE_KEY: Get from Supabase Dashboard → Settings → API → secret key
--    - https://whdftvcrtrsnefhprebj.supabase.co: Production Supabase URL
-- ==============================================================================

-- Step 1: Update call_weekly_close() function to be environment-aware
CREATE OR REPLACE FUNCTION public.call_weekly_close()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  request_id bigint;
  svc_key text := current_setting('app.settings.service_role_key', true);
  supabase_url text := current_setting('app.settings.supabase_url', true);
  function_url text;
BEGIN
  IF svc_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not set in app.settings';
  END IF;

  IF supabase_url IS NULL THEN
    RAISE EXCEPTION 'supabase_url not set in app.settings';
  END IF;

  -- Build the Edge Function URL
  function_url := supabase_url || '/functions/v1/bright-service';

  SELECT net.http_post(
    function_url,
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || svc_key
    ),
    '{}'::jsonb,
    30000
  ) INTO request_id;

  RAISE NOTICE 'Weekly close Edge Function called (bright-service). URL: %, Request ID: %', function_url, request_id;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error calling bright-service Edge Function: %', SQLERRM;
END;
$$;

-- Step 2: Set app.settings (required for call_weekly_close function)
-- Note: This uses ALTER DATABASE which requires superuser privileges
-- If this fails, you may need to set it manually in Supabase Dashboard
DO $$
BEGIN
    -- Set service_role_key (REPLACE WITH YOUR PRODUCTION SECRET KEY)
    EXECUTE format('ALTER DATABASE postgres SET app.settings.service_role_key = %L', 'YOUR_PRODUCTION_SERVICE_ROLE_KEY');
    -- Set supabase_url (production URL)
    EXECUTE format('ALTER DATABASE postgres SET app.settings.supabase_url = %L', 'https://whdftvcrtrsnefhprebj.supabase.co');
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'Cannot set app.settings via SQL. Please set it manually in Supabase Dashboard → Database → Settings → Database Settings → Custom Postgres Config';
        RAISE NOTICE 'Required settings: app.settings.service_role_key and app.settings.supabase_url';
    WHEN OTHERS THEN
        RAISE WARNING 'Error setting app.settings: %', SQLERRM;
END;
$$;

-- Step 3: Remove existing cron job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-production';

-- Step 4: Schedule new cron job
-- Schedule: Every Monday at 17:00 UTC (12:00 PM EST / 1:00 PM EDT)
-- Cron format: minute hour day-of-month month day-of-week
-- 0 17 * * 1 = Every Monday at 17:00 UTC
SELECT cron.schedule(
    'weekly-close-production',           -- Job name
    '0 17 * * 1',                         -- Schedule: Every Monday at 17:00 UTC
    $$SELECT public.call_weekly_close();$$  -- Call the function
);

-- Step 5: Verify the job was created
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active,
    nodename,
    nodeport
FROM cron.job
WHERE jobname = 'weekly-close-production';



