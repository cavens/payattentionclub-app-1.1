-- Enable Testing Mode
-- This sets testing_mode in app_config table for database functions
-- Edge Functions also need TESTING_MODE=true in Supabase secrets

-- Insert or update testing_mode in app_config
INSERT INTO public.app_config (key, value, description)
VALUES ('testing_mode', 'true', 'Enable compressed timeline testing (3 min week, 1 min grace)')
ON CONFLICT (key) 
DO UPDATE SET 
  value = 'true',
  description = 'Enable compressed timeline testing (3 min week, 1 min grace)',
  updated_at = NOW();

-- Verify it's set
SELECT key, value, description 
FROM public.app_config 
WHERE key = 'testing_mode';

-- Expected: Should show testing_mode = 'true'


