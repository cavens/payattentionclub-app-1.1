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
    p_apps_to_limit jsonb DEFAULT '{}'::jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deadline_ts timestamptz;
    v_app_count integer;
    v_max_charge_cents integer;
BEGIN
    -- Calculate deadline timestamp (noon EST on the deadline date)
    v_deadline_ts := (p_deadline_date::timestamp AT TIME ZONE 'America/New_York') + INTERVAL '12 hours';
    
    -- Count apps and categories
    v_app_count := COALESCE(jsonb_array_length(p_apps_to_limit->'app_bundle_ids'), 0)
                 + COALESCE(jsonb_array_length(p_apps_to_limit->'categories'), 0);
    
    -- Call the internal calculation function (single source of truth)
    v_max_charge_cents := public.calculate_max_charge_cents(
        v_deadline_ts,
        p_limit_minutes,
        p_penalty_per_minute_cents,
        v_app_count
    );
    
    -- Return as JSON
    RETURN json_build_object(
        'max_charge_cents', v_max_charge_cents,
        'max_charge_dollars', v_max_charge_cents / 100.0,
        'deadline_date', p_deadline_date,
        'limit_minutes', p_limit_minutes,
        'penalty_per_minute_cents', p_penalty_per_minute_cents,
        'app_count', v_app_count
    );
END;
$$;

-- Grant execute to authenticated users (they need to preview before committing)
GRANT EXECUTE ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, jsonb) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, jsonb) IS 
'Preview the max charge amount before creating a commitment.
Returns the same value that would be stored in max_charge_cents when committing.
Call this from the frontend to display the authorization amount to the user.';

