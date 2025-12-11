-- ==============================================================================
-- Set Service Role Key for Staging (Alternative Method)
-- ==============================================================================
-- Since we can't set app.settings.service_role_key via SQL or UI,
-- we'll store it in a table instead
-- ==============================================================================

-- Create the config table if it doesn't exist
CREATE TABLE IF NOT EXISTS public._internal_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert or update the service role key for staging
-- ⚠️ IMPORTANT: Replace YOUR_STAGING_SERVICE_ROLE_KEY with the actual key from your .env file
-- DO NOT commit actual keys to git!
INSERT INTO public._internal_config (key, value) 
VALUES (
    'service_role_key', 
    'YOUR_STAGING_SERVICE_ROLE_KEY_FROM_ENV'
)
ON CONFLICT (key) DO UPDATE 
SET value = EXCLUDED.value, updated_at = NOW();

-- Verify it was set
SELECT key, 
       LEFT(value, 20) || '...' as value_preview,
       updated_at
FROM public._internal_config
WHERE key = 'service_role_key';

