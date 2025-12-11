-- ==============================================================================
-- Internal Function: calculate_max_charge_cents
-- ==============================================================================
-- THE single source of truth for max charge calculation.
-- Used by both rpc_preview_max_charge and rpc_create_commitment.
--
-- Formula based on ARCHITECTURE.md:
--   - Lower time limit → higher authorization (more potential overage)
--   - Higher penalty per minute → higher authorization
--   - More apps selected → higher authorization (risk factor)
--   - More time until deadline → higher authorization
--   - Minimum: $5.00 (500 cents)
--   - Maximum: $1000.00 (100000 cents)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.calculate_max_charge_cents(
    p_deadline_ts timestamptz,
    p_limit_minutes integer,
    p_penalty_per_minute_cents integer,
    p_app_count integer
)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_hours_remaining numeric;
    v_limit_hours numeric;
    v_daily_potential_overage_hours numeric;
    v_days_remaining numeric;
    v_risk_factor numeric;
    v_base_amount_cents numeric;
    v_result_cents integer;
BEGIN
    -- Calculate hours remaining until deadline
    v_hours_remaining := GREATEST(0, EXTRACT(EPOCH FROM (p_deadline_ts - NOW())) / 3600.0);
    
    -- If no time remaining, return 0
    IF v_hours_remaining <= 0 THEN
        RETURN 0;
    END IF;
    
    -- Convert limit to hours
    v_limit_hours := p_limit_minutes / 60.0;
    
    -- Calculate days remaining (for scaling)
    v_days_remaining := v_hours_remaining / 24.0;
    
    -- Risk factor based on app count (1.0 base + 0.05 per app, capped at 2.0)
    v_risk_factor := LEAST(2.0, 1.0 + 0.05 * COALESCE(p_app_count, 0));
    
    -- Calculate realistic daily potential overage
    -- Assume user could realistically use apps 8-12 hours per day
    -- Daily potential overage = max(0, realistic_daily_usage - daily_limit)
    -- If limit is 21 hours/week = 3 hours/day, overage could be ~9 hours/day
    v_daily_potential_overage_hours := GREATEST(0, 10 - (v_limit_hours / GREATEST(1, v_days_remaining)));
    
    -- Base calculation:
    -- (daily_overage_hours * 60 minutes * penalty_per_minute) * days_remaining * risk_factor
    -- But capped to be reasonable
    v_base_amount_cents := 
        v_daily_potential_overage_hours 
        * 60.0 
        * p_penalty_per_minute_cents 
        * LEAST(7, v_days_remaining)  -- Cap at 7 days worth
        * v_risk_factor;
    
    -- Apply bounds: minimum $5 (500 cents), maximum $1000 (100000 cents)
    v_result_cents := GREATEST(500, LEAST(100000, FLOOR(v_base_amount_cents)::integer));
    
    RETURN v_result_cents;
END;
$$;

-- Add comment explaining the function
COMMENT ON FUNCTION public.calculate_max_charge_cents(timestamptz, integer, integer, integer) IS 
'Calculates the maximum charge (authorization amount) in cents for a commitment.
This is THE single source of truth - used by both preview and commitment creation.
Returns value between 500 ($5) and 10000 ($100) cents.';

