-- ==============================================================================
-- Migration: Create app_config table for secure configuration storage
-- Date: 2026-01-11
-- Purpose: Store service role key and Supabase URL securely (alternative to app.settings)
-- ==============================================================================
-- 
-- This table stores configuration values that RPC functions need but can't access
-- via app.settings (which requires superuser privileges).
-- 
-- Security:
-- - RLS enabled: Only service role can read (via SECURITY DEFINER functions)
-- - No user access: Regular users cannot read these values
-- - Secrets stored encrypted at rest (PostgreSQL default)
-- 
-- Usage:
-- - Populate via script: scripts/setup_app_config.sh
-- - Read in RPC functions: SELECT value FROM app_config WHERE key = 'service_role_key'
-- ==============================================================================

-- Create app_config table
CREATE TABLE IF NOT EXISTS public.app_config (
  key text PRIMARY KEY,
  value text, -- Nullable - will be populated by setup script
  description text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text -- Track who/what updated it
);

-- Enable RLS
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Deny all access by default
-- SECURITY DEFINER functions can still read (they bypass RLS)
-- Regular users cannot read these secrets
CREATE POLICY "No user access to app_config"
  ON public.app_config
  FOR ALL
  USING (false); -- Deny all access to regular users

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_app_config_key ON public.app_config(key);

-- Add comments
COMMENT ON TABLE public.app_config IS 
'Stores secure configuration values for RPC functions.
Only accessible via SECURITY DEFINER functions (service role context).
Regular users cannot read these values due to RLS policies.';

COMMENT ON COLUMN public.app_config.key IS 
'Configuration key (e.g., "service_role_key", "supabase_url")';

COMMENT ON COLUMN public.app_config.value IS 
'Configuration value (secrets stored here - encrypted at rest by PostgreSQL)';

-- Insert default keys (with NULL values - must be populated via script)
INSERT INTO public.app_config (key, value, description, updated_by)
VALUES 
  ('service_role_key', NULL, 'Supabase service role key for Edge Function authentication', 'migration'),
  ('supabase_url', NULL, 'Supabase project URL for Edge Function calls', 'migration')
ON CONFLICT (key) DO NOTHING;

