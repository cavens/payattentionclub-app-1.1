-- ==============================================================================
-- RPC Function to List Cron Jobs
-- ==============================================================================
-- Returns all cron jobs as JSON for easy inspection
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_list_cron_jobs()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'jobid', j.jobid,
            'jobname', j.jobname,
            'schedule', j.schedule,
            'command', j.command,
            'active', j.active,
            'nodename', j.nodename,
            'nodeport', j.nodeport
        ) ORDER BY j.jobid
    ) INTO v_result
    FROM cron.job j;
    
    RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.rpc_list_cron_jobs() TO service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_cron_jobs() FROM anon, authenticated;

