-- ==============================================================================
-- Setup Personal Access Token (PAT) for Automatic Secret Updates
-- ==============================================================================
-- This script stores a Personal Access Token in app_config so that the
-- update-secret Edge Function can automatically update Edge Function secrets
-- via the Supabase Management API.
--
-- Steps:
-- 1. Generate a PAT: https://supabase.com/dashboard/account/tokens
-- 2. Replace 'YOUR_PAT_TOKEN_HERE' below with your actual PAT
-- 3. Run this script
-- ==============================================================================

-- Store PAT in app_config table
INSERT INTO app_config (key, value, description, updated_at)
VALUES (
  'supabase_access_token',
  'YOUR_PAT_TOKEN_HERE',  -- ⚠️ REPLACE THIS with your actual PAT from https://supabase.com/dashboard/account/tokens
  'Personal Access Token for Supabase Management API (used to update Edge Function secrets via update-secret Edge Function)',
  NOW()
)
ON CONFLICT (key) DO UPDATE 
SET value = EXCLUDED.value, 
    description = EXCLUDED.description,
    updated_at = NOW();

-- Verify the PAT was stored (value is hidden for security)
SELECT 
  key,
  CASE 
    WHEN key = 'supabase_access_token' THEN '***HIDDEN***'
    ELSE value
  END AS value_preview,
  description,
  updated_at,
  CASE 
    WHEN value IS NOT NULL AND value != '' THEN '✅ PAT is set'
    ELSE '❌ PAT is missing or empty'
  END AS status
FROM app_config
WHERE key = 'supabase_access_token';

-- ==============================================================================
-- Next Steps:
-- ==============================================================================
-- 1. Test the toggle in the dashboard
-- 2. Check that both app_config.testing_mode AND Edge Function secret TESTING_MODE update
-- 3. If it works, you'll see "secret_updated": true in the response
-- ==============================================================================

