-- ==============================================================================
-- RPC Function to Verify Environment Setup
-- ==============================================================================
-- Returns a comprehensive status of the environment setup
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_verify_setup()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_tables JSON;
    v_functions JSON;
    v_service_key BOOLEAN;
BEGIN
    -- Check required tables
    SELECT json_agg(table_name ORDER BY table_name) INTO v_tables
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
      AND table_name IN (
          'commitments',
          'daily_usage',
          'user_week_penalties',
          'weekly_pools',
          'payments',
          'users',
          '_internal_config'
      );
    
    -- Check key RPC functions
    SELECT json_agg(routine_name ORDER BY routine_name) INTO v_functions
    FROM information_schema.routines
    WHERE routine_schema = 'public'
      AND routine_type = 'FUNCTION'
      AND routine_name IN (
          'rpc_create_commitment',
          'rpc_sync_daily_usage',
          'rpc_get_week_status',
          'rpc_delete_user_completely',
          'call_weekly_close',
          'rpc_list_cron_jobs',
          'rpc_get_cron_history'
      );
    
    -- Check service role key
    SELECT EXISTS (
        SELECT 1 FROM public._internal_config 
        WHERE key = 'service_role_key' AND value IS NOT NULL
    ) INTO v_service_key;
    
    -- Build result
    SELECT json_build_object(
        'tables', COALESCE(v_tables, '[]'::json),
        'tables_count', json_array_length(COALESCE(v_tables, '[]'::json)),
        'tables_expected', 7,
        'functions', COALESCE(v_functions, '[]'::json),
        'functions_count', json_array_length(COALESCE(v_functions, '[]'::json)),
        'functions_expected', 7,
        'service_role_key_set', v_service_key,
        'status', CASE 
            WHEN json_array_length(COALESCE(v_tables, '[]'::json)) = 7 
                 AND json_array_length(COALESCE(v_functions, '[]'::json)) >= 6
                 AND v_service_key = true
            THEN 'complete'
            ELSE 'incomplete'
        END
    ) INTO v_result;
    
    RETURN v_result;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.rpc_verify_setup() TO service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_verify_setup() FROM anon, authenticated;


