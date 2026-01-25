-- ==============================================================================
-- RPC Function: rpc_create_commitment
-- ==============================================================================
-- Creates a new commitment for the authenticated user.
-- Uses calculate_max_charge_cents() for the max charge calculation (single source of truth).
-- 
-- ALIGNED WITH TESTING MODE: Both modes now use the same structure:
-- - p_deadline_timestamp: Required timestamp (testing: now+4min, normal: next Monday 12:00 ET)
-- - p_grace_duration_hours: Required grace duration (testing: 0.0167, normal: 24)
-- - week_end_timestamp: Primary storage (not week_end_date)
-- ==============================================================================

-- Drop old function signatures first (required when changing parameter list)
DROP FUNCTION IF EXISTS public.rpc_create_commitment(date, integer, integer, integer, jsonb, text, timestamptz);
DROP FUNCTION IF EXISTS public.rpc_create_commitment(date, integer, integer, integer, jsonb, text);
DROP FUNCTION IF EXISTS public.rpc_create_commitment(date, integer, integer, jsonb, text);  -- 5-param version (missing p_app_count)
DROP FUNCTION IF EXISTS public.rpc_create_commitment(date, integer, integer, jsonb);

CREATE OR REPLACE FUNCTION public.rpc_create_commitment(
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_app_count integer,  -- Explicit app count parameter (single source of truth)
  p_apps_to_limit jsonb,  -- Keep for storage in commitments table
  p_deadline_timestamp timestamptz,  -- REQUIRED: Full timestamp (both modes)
  p_grace_duration_hours numeric,  -- REQUIRED: Grace duration in hours (testing: 0.0167, normal: 24)
  p_saved_payment_method_id text DEFAULT NULL  -- Optional: Payment method ID
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_pm boolean;
  v_commitment_start_date date;
  v_deadline_ts timestamptz;
  v_grace_expires_at timestamptz;
  v_max_charge_cents integer;
  v_commitment_id uuid;
  v_result json;
  v_week_end_date date;  -- Derived from timestamp for weekly_pools
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Check user has active payment method
  SELECT u.has_active_payment_method
    INTO v_has_pm
    FROM public.users u
    WHERE u.id = v_user_id;

  IF COALESCE(v_has_pm, false) = false THEN
    RAISE EXCEPTION 'User has no active payment method' USING ERRCODE = 'P0001';
  END IF;

  -- 3) Set dates
  v_commitment_start_date := current_date;
  
  -- Unified logic: Always use timestamp (both modes now provide it)
  v_deadline_ts := p_deadline_timestamp;
  
  -- Unified grace calculation: deadline + duration (same formula, different values)
  v_grace_expires_at := v_deadline_ts + (p_grace_duration_hours || ' hours')::interval;
  
  -- Derive week_end_date from timestamp for weekly_pools (if needed)
  v_week_end_date := DATE(p_deadline_timestamp AT TIME ZONE 'America/New_York');

  -- 4) Use explicit p_app_count parameter (single source of truth from client)
  -- No longer extracting from JSONB arrays to avoid discrepancies

  -- 5) Calculate max charge using the SINGLE SOURCE OF TRUTH function
  v_max_charge_cents := public.calculate_max_charge_cents(
    v_deadline_ts,
    p_limit_minutes,
    p_penalty_per_minute_cents,
    p_app_count  -- Use explicit parameter
  );

  -- 6) Ensure weekly_pools entry exists (create or update to open if exists)
  -- Use derived date from timestamp
  INSERT INTO public.weekly_pools (
    week_start_date,
    total_penalty_cents,
    status
  )
  values (
    v_week_end_date,  -- Derived from timestamp
    0,
    'open'
  )
  ON CONFLICT (week_start_date) DO UPDATE SET
    status = 'open';

  -- 7) Create commitment
  INSERT INTO public.commitments (
    user_id,
    week_start_date,
    week_end_timestamp,
    week_grace_expires_at,
    limit_minutes,
    penalty_per_minute_cents,
    apps_to_limit,
    status,
    monitoring_status,
    monitoring_revoked_at,
    autocharge_consent_at,
    max_charge_cents,
    saved_payment_method_id,
    created_at
  )
  values (
    v_user_id,
    v_commitment_start_date,
    p_deadline_timestamp,  -- Store timestamp (required, both modes)
    v_grace_expires_at,     -- Store calculated grace period expiration
    p_limit_minutes,
    p_penalty_per_minute_cents,
    p_apps_to_limit,
    'pending',
    'ok',
    null,
    now(),
    v_max_charge_cents,
    p_saved_payment_method_id,
    now()
  )
  RETURNING id INTO v_commitment_id;

  -- 8) Return the created commitment
  SELECT row_to_json(c.*) INTO v_result
  FROM public.commitments c
  WHERE c.id = v_commitment_id;

  RETURN v_result;
END;
$$;

-- Add comment
COMMENT ON FUNCTION public.rpc_create_commitment(integer, integer, integer, jsonb, timestamptz, numeric, text) IS 
'Creates a new commitment for the authenticated user.
ALIGNED WITH TESTING MODE: Both modes use the same structure and logic.

Parameters:
- p_deadline_timestamp: REQUIRED timestamp (testing: now+4min, normal: next Monday 12:00 ET)
- p_grace_duration_hours: REQUIRED grace duration in hours (testing: 0.0167, normal: 24)

Uses explicit p_app_count parameter (single source of truth from client).
Uses calculate_max_charge_cents() for the max charge calculation (single source of truth).
Stores week_end_timestamp as primary source of truth (week_end_date removed).
Calculates week_grace_expires_at as: deadline_timestamp + grace_duration_hours (unified formula).

This ensures preview and commitment creation use the exact same formula and app count.
Both testing and normal mode use identical logic, only time values differ.';


