-- ==============================================================================
-- Test if search_path is being set correctly in the function
-- ==============================================================================
-- This will help us understand if set_config is working in cron context
-- ==============================================================================

-- Create a test function to check search_path
CREATE OR REPLACE FUNCTION public.test_search_path()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  current_path text;
BEGIN
  -- Get current search_path
  SHOW search_path INTO current_path;
  
  -- Try to set it
  PERFORM set_config('search_path', 'public, net, extensions', true);
  
  -- Get search_path again
  SHOW search_path INTO current_path;
  
  RETURN 'Search path: ' || current_path;
END;
$$;

-- Run it to see what search_path is
SELECT public.test_search_path();

-- Also test if net.http_post is accessible
-- (commented out to avoid actual HTTP call)
/*
SELECT net.http_post(
  url := 'https://httpbin.org/post',
  headers := jsonb_build_object('Content-Type', 'application/json'),
  body := '{}'::jsonb
);
*/

