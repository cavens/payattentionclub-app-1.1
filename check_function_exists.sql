-- Check if the function exists
SELECT 
    routine_name,
    routine_type,
    routine_schema
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'rpc_setup_test_data';


