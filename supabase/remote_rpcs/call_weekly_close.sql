-- Requires app_config table to be configured:
-- Run scripts/setup_app_config.sh to populate service_role_key and supabase_url

CREATE OR REPLACE FUNCTION public.call_weekly_close()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  request_id bigint;
  svc_key text;
  supabase_url text;
  function_url text;
BEGIN
  -- Get settings from app_config table (secure alternative to app.settings)
  -- SECURITY DEFINER functions can read from app_config despite RLS
  SELECT value INTO svc_key
  FROM public.app_config
  WHERE key = 'service_role_key';
  
  SELECT value INTO supabase_url
  FROM public.app_config
  WHERE key = 'supabase_url';

  IF svc_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not set in app_config. Run scripts/setup_app_config.sh to configure.';
  END IF;

  IF supabase_url IS NULL THEN
    RAISE EXCEPTION 'supabase_url not set in app_config. Run scripts/setup_app_config.sh to configure.';
  END IF;

  -- Build the Edge Function URL
  function_url := supabase_url || '/functions/v1/bright-service';

  -- Correct signature: net.http_post(url, body, params, headers, timeout_milliseconds)
  SELECT net.http_post(
    function_url,                                    -- url
    '{}'::jsonb,                                     -- body
    '{}'::jsonb,                                     -- params
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || svc_key
    ),                                               -- headers
    30000                                            -- timeout_milliseconds (30 seconds)
  ) INTO request_id;

  RAISE NOTICE 'Weekly close Edge Function called (bright-service). URL: %, Request ID: %', function_url, request_id;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error calling bright-service Edge Function: %', SQLERRM;
END;
$$;


