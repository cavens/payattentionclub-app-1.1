-- ==============================================================================
-- Fixed call_weekly_close() function that doesn't require app.settings
-- ==============================================================================
-- This version stores the service role key in a table instead of database config
-- ==============================================================================

-- Step 1: Create a table to store the service role key
CREATE TABLE IF NOT EXISTS public._internal_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 2: Insert service role key (run this for each environment)
-- ⚠️ IMPORTANT: Replace YOUR_SERVICE_ROLE_KEY with the actual key from your .env file
-- DO NOT commit actual keys to git!

-- STAGING:
-- INSERT INTO public._internal_config (key, value) 
-- VALUES ('service_role_key', 'YOUR_STAGING_SERVICE_ROLE_KEY_FROM_ENV')
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- PRODUCTION:
-- INSERT INTO public._internal_config (key, value) 
-- VALUES ('service_role_key', 'YOUR_PRODUCTION_SERVICE_ROLE_KEY_FROM_ENV')
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- Step 3: Create/update the function to read from the table
CREATE OR REPLACE FUNCTION public.call_weekly_close()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  request_id bigint;
  svc_key text;
  project_url text;
BEGIN
  -- Get service role key from table
  SELECT value INTO svc_key
  FROM public._internal_config
  WHERE key = 'service_role_key';
  
  IF svc_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not set in _internal_config table. Please run: INSERT INTO public._internal_config (key, value) VALUES (''service_role_key'', ''YOUR_KEY'');';
  END IF;
  
  -- Determine project URL based on the service role key (extract from JWT)
  -- For staging: auqujbppoytkeqdsgrbl
  -- For production: whdftvcrtrsnefhprebj
  -- We'll detect based on the key value
  IF svc_key LIKE '%auqujbppoytkeqdsgrbl%' THEN
    project_url := 'https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/weekly-close';
  ELSIF svc_key LIKE '%whdftvcrtrsnefhprebj%' THEN
    project_url := 'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close';
  ELSE
    RAISE EXCEPTION 'Could not determine project URL from service role key';
  END IF;

  SELECT net.http_post(
    project_url,
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

-- Step 4: Grant necessary permissions
GRANT SELECT ON public._internal_config TO service_role;
GRANT SELECT ON public._internal_config TO authenticated;

