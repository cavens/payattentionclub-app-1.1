-- ==============================================================================
-- Internal Function: calculate_max_charge_cents
-- ==============================================================================
-- THE single source of truth for max charge calculation.
-- Used by both rpc_preview_max_charge and rpc_create_commitment.
--
-- Formula:
--   - Weekly limit (not daily) - this is the key fix
--   - Lower time limit → higher authorization (more potential overage)
--   - Higher penalty per minute → higher authorization
--   - More apps selected → higher authorization (risk factor)
--   - More time until deadline → higher authorization
--   - Minimum: $5.00 (500 cents)
--   - Maximum: $1000.00 (100000 cents)
--
-- The calculation estimates potential overage based on:
--   1. Weekly limit (p_limit_minutes) - this is the TOTAL allowed for the week
--   2. Time remaining until deadline (more time = more potential overage)
--   3. Realistic maximum usage assumption (scaled by time remaining)
--   4. Risk factor based on number of apps selected
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
    v_minutes_remaining numeric;
    v_days_remaining numeric;
    v_limit_minutes numeric;
    v_risk_factor numeric;
    v_potential_usage_minutes numeric;
    v_potential_overage_minutes numeric;
    v_base_amount_cents numeric;
    v_result_cents integer;
BEGIN
    -- Calculate minutes remaining until deadline
    v_minutes_remaining := GREATEST(0, EXTRACT(EPOCH FROM (p_deadline_ts - NOW())) / 60.0);
    
    -- If no time remaining, return 0
    IF v_minutes_remaining <= 0 THEN
        RETURN 0;
    END IF;
    
    -- Calculate days remaining (for scaling)
    v_days_remaining := v_minutes_remaining / (24.0 * 60.0);
    
    -- Weekly limit in minutes (this is the TOTAL allowed for the entire week)
    v_limit_minutes := p_limit_minutes;
    
    -- Risk factor based on app count (1.0 base + 0.05 per app, capped at 1.6)
    -- More apps = higher risk of overage, but keep it reasonable
    v_risk_factor := LEAST(1.6, 1.0 + 0.05 * COALESCE(p_app_count, 0));
    
    -- Calculate realistic potential usage for the remaining time
    -- Assumption: In worst case, user could use apps for up to 4.3 hours/day
    -- This is a reasonable maximum for heavy usage (not 24/7)
    -- Scale by days remaining (but cap at 7 days to avoid extreme values)
    v_potential_usage_minutes := LEAST(7.0, v_days_remaining) * 4.3 * 60.0;
    
    -- Potential overage = max(0, potential_usage - weekly_limit)
    -- This represents how much they could go over their WEEKLY limit
    v_potential_overage_minutes := GREATEST(0, v_potential_usage_minutes - v_limit_minutes);
    
    -- Base calculation with damping:
    -- If there's potential overage, use that
    -- If no overage (limit is very high), still calculate based on penalty rate and time remaining
    -- This ensures high penalty rates result in appropriate authorization even with high limits
    IF v_potential_overage_minutes > 0 THEN
        -- Normal case: calculate based on overage
        v_base_amount_cents := 
            v_potential_overage_minutes 
            * p_penalty_per_minute_cents 
            * v_risk_factor
            * LEAST(1.15, 1.0 + (SQRT(v_days_remaining / 7.0) * 0.15)) -- Scale up to 1.15x for longer periods
            * 0.87; -- Additional damping to keep standard settings around $65
    ELSE
        -- No overage possible (limit is very high relative to time remaining)
        -- Still calculate based on penalty rate, time remaining, and risk
        -- Use a fraction of potential usage as a base (e.g., 20% of potential usage)
        -- This ensures high penalty rates are reflected even when limit can't be exceeded
        v_base_amount_cents := 
            (v_potential_usage_minutes * 0.2) -- Use 20% of potential usage as base
            * p_penalty_per_minute_cents 
            * v_risk_factor
            * LEAST(1.15, 1.0 + (SQRT(v_days_remaining / 7.0) * 0.15))
            * 0.87;
    END IF;
    
    -- Apply bounds: minimum $5 (500 cents), maximum $1000 (100000 cents)
    v_result_cents := GREATEST(500, LEAST(100000, FLOOR(v_base_amount_cents)::integer));
    
    RETURN v_result_cents;
END;
$$;

-- Add comment explaining the function
COMMENT ON FUNCTION public.calculate_max_charge_cents(timestamptz, integer, integer, integer) IS 
'Calculates the maximum charge (authorization amount) in cents for a commitment.
This is THE single source of truth - used by both preview and commitment creation.
Returns value between 500 ($5) and 100000 ($1000) cents.';

