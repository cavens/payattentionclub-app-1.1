-- ==============================================================================
-- RPC Function: rpc_preview_max_charge
-- ==============================================================================
-- Preview the max charge amount BEFORE creating a commitment.
-- Frontend calls this to display the authorization amount to the user.
-- Uses the same calculate_max_charge_cents() function as rpc_create_commitment.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_preview_max_charge(
    p_deadline_date date,
    p_limit_minutes integer,
    p_penalty_per_minute_cents integer,
    p_app_count integer,  -- Explicit app count parameter (single source of truth)
    p_apps_to_limit jsonb DEFAULT '{}'::jsonb  -- Keep for backward compatibility/storage
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deadline_ts timestamptz;
    v_max_charge_cents integer;
BEGIN
    -- Calculate deadline timestamp (noon EST on the deadline date)
    v_deadline_ts := (p_deadline_date::timestamp AT TIME ZONE 'America/New_York') + INTERVAL '12 hours';
    
    -- Use explicit p_app_count parameter (single source of truth from client)
    -- No longer extracting from JSONB arrays to avoid discrepancies
    
    -- Call the internal calculation function (single source of truth)
    v_max_charge_cents := public.calculate_max_charge_cents(
        v_deadline_ts,
        p_limit_minutes,
        p_penalty_per_minute_cents,
        p_app_count  -- Use explicit parameter
    );
    
    -- Return as JSON
    RETURN json_build_object(
        'max_charge_cents', v_max_charge_cents,
        'max_charge_dollars', v_max_charge_cents / 100.0,
        'deadline_date', p_deadline_date,
        'limit_minutes', p_limit_minutes,
        'penalty_per_minute_cents', p_penalty_per_minute_cents,
        'app_count', p_app_count  -- Return the explicit count
    );
END;
$$;

-- Grant execute to authenticated and anonymous users (preview should work before committing)
GRANT EXECUTE ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, integer, jsonb) TO authenticated, anon;

-- Add comment
COMMENT ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, integer, jsonb) IS 
'Preview the max charge amount before creating a commitment.
Uses explicit p_app_count parameter (single source of truth from client).
Returns the same value that would be stored in max_charge_cents when committing.
Call this from the frontend to display the authorization amount to the user.';

