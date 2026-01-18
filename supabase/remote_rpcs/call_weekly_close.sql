-- Requires app.settings.service_role_key to be set:
-- ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_SERVICE_ROLE_KEY';

CREATE OR REPLACE FUNCTION public.call_weekly_close()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  request_id bigint;
  svc_key text := current_setting('app.settings.service_role_key', true);
BEGIN
  IF svc_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not set';
  END IF;

  SELECT net.http_post(
    'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close',
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || svc_key
    ),
    '{}'::jsonb,
    30000
  ) INTO request_id;

  RAISE NOTICE 'Weekly close Edge Function called. Request ID: %', request_id;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error calling weekly-close Edge Function: %', SQLERRM;
END;
$$;


