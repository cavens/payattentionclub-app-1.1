-- Verify if call_weekly_close function has been fixed (no placeholders)

SELECT pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'call_weekly_close'
  AND pronamespace = 'public'::regnamespace;

-- Check if it still has placeholders
SELECT 
  CASE 
    WHEN pg_get_functiondef(oid) LIKE '%YOUR_PROJECT%' THEN '❌ Still has YOUR_PROJECT placeholder'
    WHEN pg_get_functiondef(oid) LIKE '%YOUR_SERVICE_ROLE_KEY%' THEN '❌ Still has YOUR_SERVICE_ROLE_KEY placeholder'
    WHEN pg_get_functiondef(oid) LIKE '%whdftvcrtrsnefhprebj%' THEN '✅ Project URL is correct'
    ELSE '⚠️ Unknown status'
  END as status
FROM pg_proc
WHERE proname = 'call_weekly_close'
  AND pronamespace = 'public'::regnamespace;


