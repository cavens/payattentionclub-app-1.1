-- Fix call_weekly_close function with correct project URL
-- IMPORTANT: Replace YOUR_SERVICE_ROLE_KEY_HERE with your actual service role key
-- Get it from: Supabase Dashboard → Settings → API → service_role key

CREATE OR REPLACE FUNCTION public.call_weekly_close()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  request_id bigint;
BEGIN
  -- Make HTTP POST request to weekly-close Edge Function
  SELECT net.http_post(
    'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close',  -- Your project URL
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY_HERE'  -- ⚠️ REPLACE THIS with your service_role key
    ),
    '{}'::jsonb,
    30000  -- 30 second timeout
  ) INTO request_id;
  
  -- Log that request was queued
  RAISE NOTICE 'Weekly close Edge Function called. Request ID: %', request_id;
  
  -- Note: pg_net processes requests asynchronously
  -- The response will be available in net.http_response_queue later
  -- For cron jobs, we just need to trigger the request
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error calling weekly-close Edge Function: %', SQLERRM;
END;
$function$;
