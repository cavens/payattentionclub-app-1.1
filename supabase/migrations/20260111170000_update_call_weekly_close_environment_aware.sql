-- Migration: Update call_weekly_close() to be environment-aware
-- 
-- Changes:
-- - Reads app.settings.supabase_url to determine which Edge Function to call
-- - Builds URL dynamically: supabase_url || '/functions/v1/bright-service'
-- - Validates both service_role_key and supabase_url are set
--
-- Requires app.settings to be configured:
--   ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_SERVICE_ROLE_KEY';
--   ALTER DATABASE postgres SET app.settings.supabase_url = 'https://YOUR_PROJECT_REF.supabase.co';

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



