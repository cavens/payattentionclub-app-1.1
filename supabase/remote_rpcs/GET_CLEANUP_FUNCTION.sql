-- Run this query in Supabase SQL Editor to get the function definition
-- Then copy the result and create rpc_cleanup_test_data.sql

SELECT 
    pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'rpc_cleanup_test_data'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
