-- ==============================================================================
-- Migration: Update calculate_max_charge_cents function
-- ==============================================================================
-- Date: 2025-12-31
-- Purpose: Update authorization amount calculation with new formula
-- Baseline: 21h @ $0.10, 4 apps = ~$20
-- Key improvements:
--   1. Aggressive strictness scaling (24h to 12h = $24.28 difference)
--   2. Minimum 1 app required (zero apps not possible)
--   3. Logical relationships between all factors
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
    v_max_usage_minutes numeric;
    v_potential_overage_minutes numeric;
    v_strictness_ratio numeric;
    v_strictness_multiplier numeric;
    v_risk_factor numeric;
    v_time_factor numeric;
    v_base_amount_cents numeric;
    v_result_cents integer;
BEGIN
    -- Calculate minutes remaining until deadline
    v_minutes_remaining := GREATEST(0, EXTRACT(EPOCH FROM (p_deadline_ts - NOW())) / 60.0);
    
    -- If no time remaining, return minimum
    IF v_minutes_remaining <= 0 THEN
        RETURN 1500; -- $15 minimum
    END IF;
    
    -- Calculate days remaining (for scaling)
    v_days_remaining := v_minutes_remaining / (24.0 * 60.0);
    
    -- Maximum realistic usage: 12 hours/day (720 minutes/day)
    -- Cap at 7 days to avoid extreme values for longer periods
    v_max_usage_minutes := LEAST(7.0, v_days_remaining) * 720.0;
    
    -- Potential overage = max(0, max_usage - limit)
    -- Stricter limits (lower limit_minutes) = more potential overage
    v_potential_overage_minutes := GREATEST(0, v_max_usage_minutes - p_limit_minutes);
    
    -- Calculate strictness multiplier (aggressive scaling for stricter limits)
    -- strictness_ratio = max_usage / limit_minutes
    -- strictness_multiplier = strictness_ratio × 0.4
    -- Examples:
    --   24h limit: (5,040 / 1,440) × 0.4 = 1.4x
    --   21h limit: (5,040 / 1,260) × 0.4 = 1.6x
    --   15h limit: (5,040 / 900) × 0.4 = 2.24x
    --   12h limit: (5,040 / 720) × 0.4 = 2.8x
    v_strictness_ratio := v_max_usage_minutes / GREATEST(1, p_limit_minutes);
    v_strictness_multiplier := v_strictness_ratio * 0.4;
    
    -- Base calculation: overage × penalty × strictness_multiplier
    v_base_amount_cents := v_potential_overage_minutes * p_penalty_per_minute_cents * v_strictness_multiplier;
    
    -- Risk factor: More apps = higher risk (minimum 1 app required)
    -- Formula: 1.0 + ((app_count - 1) × 0.02)
    -- Examples:
    --   1 app  = 1.0x (baseline)
    --   4 apps = 1.06x (+6%)
    --   10 apps = 1.18x (+18%)
    --   20 apps = 1.38x (+38%)
    v_risk_factor := 1.0 + ((GREATEST(1, COALESCE(p_app_count, 1)) - 1) * 0.02);
    
    -- Time factor: More days remaining = more potential overage (1.0 to 1.2)
    -- Scales linearly: 0 days = 1.0, 7 days = 1.2
    v_time_factor := 1.0 + (LEAST(7.0, v_days_remaining) / 7.0 * 0.2);
    
    -- Apply factors
    v_base_amount_cents := v_base_amount_cents * v_risk_factor * v_time_factor;
    
    -- Damping factor: 0.026 to bring baseline (21h @ $0.10, 4 apps) to ~$20
    -- This accounts for the fact that users won't actually use apps 12h/day every day
    -- It's a worst-case scenario, so we dampen it to a more realistic authorization
    v_base_amount_cents := v_base_amount_cents * 0.026;
    
    -- Apply bounds: minimum $15 (1500 cents), maximum $1000 (100000 cents)
    v_result_cents := GREATEST(1500, LEAST(100000, FLOOR(v_base_amount_cents)::integer));
    
    RETURN v_result_cents;
END;
$$;

-- Update comment
COMMENT ON FUNCTION public.calculate_max_charge_cents(timestamptz, integer, integer, integer) IS 
'Calculates the maximum charge (authorization amount) in cents for a commitment.
This is THE single source of truth - used by both preview and commitment creation.
Baseline: 21h @ $0.10, 4 apps = ~$20.
Returns value between 1500 ($15) and 100000 ($1000) cents.
Uses aggressive strictness scaling: stricter limits result in exponentially higher authorization.';


