-- ==============================================================================
-- RPC Function to Execute SQL (for automation)
-- ==============================================================================
-- This allows executing SQL via REST API instead of direct psql connection
-- ⚠️  SECURITY WARNING: This gives full SQL access - use with caution!
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_execute_sql(p_sql TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_error TEXT;
BEGIN
    -- Only allow service_role to use this (check via JWT)
    -- In production, you might want additional security checks
    
    BEGIN
        -- Execute the SQL
        EXECUTE p_sql;
        
        -- Return success
        RETURN json_build_object(
            'success', true,
            'message', 'SQL executed successfully'
        );
    EXCEPTION
        WHEN OTHERS THEN
            -- Return error details
            RETURN json_build_object(
                'success', false,
                'error', SQLERRM,
                'sqlstate', SQLSTATE
            );
    END;
END;
$$;

-- Grant execute permission to service_role only
GRANT EXECUTE ON FUNCTION public.rpc_execute_sql(TEXT) TO service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_execute_sql(TEXT) FROM anon, authenticated;

