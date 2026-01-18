-- Disable Testing Mode
-- This sets testing_mode in app_config table for database functions
-- Edge Functions also need TESTING_MODE removed or set to false in Supabase secrets

-- Update testing_mode in app_config
UPDATE public.app_config 
SET value = 'false',
    description = 'Normal timeline (7 day week, 24 hour grace)',
    updated_at = NOW()
WHERE key = 'testing_mode';

-- Verify it's set
SELECT key, value, description 
FROM public.app_config 
WHERE key = 'testing_mode';

-- Expected: Should show testing_mode = 'false'


