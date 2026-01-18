-- ==============================================================================
-- Migration: Fix Weekly-Settlement cron job for normal mode
-- Date: 2026-01-18
-- Purpose: Fix normal mode settlement cron to use proper authentication headers
-- ==============================================================================
-- 
-- PROBLEM:
-- The `Weekly-Settlement` cron job (jobid 2) calls bright-service directly with
-- empty headers, causing authentication failures.
-- 
-- FIX:
-- Create call_settlement_normal() function that includes proper headers for normal mode.
-- Update Weekly-Settlement cron job to use this function instead of direct call.
-- ==============================================================================

-- Create function for normal mode settlement (similar to call_settlement but for normal mode)
-- This function does NOT check testing mode and does NOT include x-manual-trigger header
CREATE OR REPLACE FUNCTION public.call_settlement_normal()
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
  
  -- Call settlement with required headers for normal mode
  -- Note: No x-manual-trigger header needed in normal mode
  SELECT net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-settlement-secret', settlement_secret  -- Required for authentication
    ),
    body := '{}'::jsonb
  ) INTO request_id;
  
  RAISE NOTICE 'Settlement triggered (normal mode). Request ID: %', request_id;
END;
$$;

-- Add comment
COMMENT ON FUNCTION public.call_settlement_normal() IS 
'Calls bright-service Edge Function to trigger settlement in normal mode.
Gets settlement_secret from app_config table.
Includes x-settlement-secret header (required for authentication).
Does NOT include x-manual-trigger header (not needed in normal mode).
Called by pg_cron weekly on Tuesday 12:00 ET for normal mode settlement.';

-- Update Weekly-Settlement cron job to use the new function
-- First, unschedule the old one
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'Weekly-Settlement';

-- Recreate with the new function call
SELECT cron.schedule(
  'Weekly-Settlement',  -- Job name
  '0 12 * * 2',         -- Tuesday at 12:00 (noon) - normal mode weekly settlement
  $$SELECT public.call_settlement_normal()$$
);

-- Verify the cron job was updated
SELECT 
  jobid,
  jobname,
  schedule,
  active,
  command
FROM cron.job 
WHERE jobname = 'Weekly-Settlement';

