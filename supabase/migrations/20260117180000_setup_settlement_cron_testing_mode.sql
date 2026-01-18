-- ==============================================================================
-- Migration: Set up cron job to automatically trigger settlement in testing mode
-- Date: 2026-01-17
-- Purpose: Automatically run settlement every 2 minutes in testing mode
-- ==============================================================================
-- 
-- This cron job:
-- - Runs every 2 minutes (fast enough for testing mode's 3-minute week + 1-minute grace)
-- - Includes x-manual-trigger: true header (required for testing mode)
-- - Includes x-settlement-secret header (required for authentication)
-- - Gets settlement secret from app_config table
-- ==============================================================================

-- Ensure required extensions are enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

-- Helper function to call settlement with proper headers
-- This function gets the settlement secret from app_config and calls bright-service
CREATE OR REPLACE FUNCTION public.call_settlement()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  svc_key text;
  supabase_url text;
  settlement_secret text;
  function_url text;
  request_id bigint;
BEGIN
  -- Explicitly set search_path to include net schema
  PERFORM set_config('search_path', 'public, net, extensions', true);

  -- Get settings from app_config
  SELECT value INTO svc_key FROM public.app_config WHERE key = 'service_role_key';
  SELECT value INTO supabase_url FROM public.app_config WHERE key = 'supabase_url';
  SELECT value INTO settlement_secret FROM public.app_config WHERE key = 'settlement_secret';
  
  IF svc_key IS NULL OR supabase_url IS NULL THEN
    RAISE WARNING 'Cannot call settlement: app_config not configured. Missing service_role_key or supabase_url';
    RETURN;
  END IF;
  
  IF settlement_secret IS NULL THEN
    RAISE WARNING 'Cannot call settlement: settlement_secret not set in app_config';
    RETURN;
  END IF;
  
  function_url := supabase_url || '/functions/v1/bright-service';
  
  -- Call settlement with required headers
  SELECT net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-manual-trigger', 'true',  -- Required for testing mode
      'x-settlement-secret', settlement_secret  -- Required for authentication
    ),
    body := '{}'::jsonb
  ) INTO request_id;
  
  RAISE NOTICE 'Settlement triggered. Request ID: %', request_id;
END;
$$;

-- Delete existing settlement cron job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'run-settlement-testing';

-- Schedule settlement for TESTING MODE (every 2 minutes)
-- This ensures settlement runs automatically after grace period expires
SELECT cron.schedule(
  'run-settlement-testing',  -- Job name
  '*/2 * * * *',             -- Every 2 minutes
  $$SELECT public.call_settlement()$$
);

-- Add comment
COMMENT ON FUNCTION public.call_settlement() IS 
'Calls bright-service Edge Function to trigger settlement.
Gets settlement_secret from app_config table.
Includes x-manual-trigger: true header (required for testing mode).
Includes x-settlement-secret header (required for authentication).
Called by pg_cron every 2 minutes in testing mode.';

-- NOTE: settlement_secret must be set in app_config table before this cron job will work.
-- Run the script to set it: deno run --allow-net --allow-env --allow-read scripts/set_settlement_secret_in_app_config.ts
-- Or set it manually with the same value as SETTLEMENT_SECRET in Supabase Edge Function secrets:
-- INSERT INTO public.app_config (key, value) 
-- VALUES ('settlement_secret', 'your-secret-value-here')
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

