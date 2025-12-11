-- ==============================================================================
-- RPC Function to Get Cron Job Execution History
-- ==============================================================================
-- Returns recent execution history for cron jobs
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_cron_history(p_jobname TEXT DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_agg(
        row_to_json(t) ORDER BY t.start_time DESC
    ) INTO v_result
    FROM (
        SELECT 
            j.jobid,
            j.jobname,
            jrd.runid,
            jrd.start_time,
            jrd.end_time,
            jrd.status,
            jrd.return_message,
            EXTRACT(EPOCH FROM (jrd.end_time - jrd.start_time)) as duration_seconds
        FROM cron.job j
        INNER JOIN cron.job_run_details jrd ON j.jobid = jrd.jobid
        WHERE (p_jobname IS NULL OR j.jobname = p_jobname)
        ORDER BY jrd.start_time DESC
        LIMIT 20
    ) t;
    
    RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.rpc_get_cron_history(TEXT) TO service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_cron_history(TEXT) FROM anon, authenticated;

