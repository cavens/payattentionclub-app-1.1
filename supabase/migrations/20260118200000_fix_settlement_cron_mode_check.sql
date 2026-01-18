-- ==============================================================================
-- Migration: Fix settlement cron job to check testing mode
-- Date: 2026-01-18
-- Purpose: Prevent settlement from running every 2 minutes in normal mode
-- ==============================================================================
-- 
-- PROBLEM:
-- The `call_settlement()` function runs every 2 minutes regardless of mode.
-- In normal mode, settlement should run weekly (Tuesday 12:00 ET), not every 2 minutes.
-- 
-- FIX:
-- Add mode check to `call_settlement()` - only run if `app_config.testing_mode = 'true'`
-- This ensures the testing mode cron job only runs when actually in testing mode.
-- ==============================================================================

-- Update call_settlement() function to check testing mode
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
  testing_mode boolean;
BEGIN
  -- Explicitly set search_path to include net schema
  PERFORM set_config('search_path', 'public, net, extensions', true);

  -- Check TESTING_MODE from app_config (if not set, default to false for normal mode)
  -- Note: TESTING_MODE should be stored as 'true' or 'false' string in app_config
  SELECT COALESCE(
    (SELECT CASE WHEN value = 'true' THEN true ELSE false END 
     FROM public.app_config WHERE key = 'testing_mode'),
    false
  ) INTO testing_mode;

  -- Only proceed if in testing mode
  -- In normal mode, settlement should be triggered by a separate weekly cron job
  IF NOT testing_mode THEN
    RAISE NOTICE 'Settlement cron skipped - not in testing mode (normal mode uses weekly cron)';
    RETURN;
  END IF;

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
  
  RAISE NOTICE 'Settlement triggered (testing mode). Request ID: %', request_id;
END;
$$;

-- Update function comment
COMMENT ON FUNCTION public.call_settlement() IS 
'Calls bright-service Edge Function to trigger settlement.
Gets settlement_secret from app_config table.
Includes x-manual-trigger: true header (required for testing mode).
Includes x-settlement-secret header (required for authentication).
ONLY runs if app_config.testing_mode = true (skips in normal mode).
Called by pg_cron every 2 minutes in testing mode only.
In normal mode, settlement should be triggered by a separate weekly cron job.';

