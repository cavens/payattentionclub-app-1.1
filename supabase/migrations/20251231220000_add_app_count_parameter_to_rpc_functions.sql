-- ==============================================================================
-- Migration: Add p_app_count Parameter to RPC Functions
-- ==============================================================================
-- Date: 2025-12-31
-- Purpose: Add explicit p_app_count parameter to rpc_preview_max_charge and
--          rpc_create_commitment to ensure single source of truth for app count.
-- 
-- This fixes the discrepancy where:
--   - Preview extracted app count from arrays correctly → $50.13
--   - Commitment creation received empty arrays → app_count = 0 → $40.42
--
-- After this migration, both functions will use the explicit p_app_count parameter
-- passed from the client, ensuring consistent authorization amounts.
-- ==============================================================================

-- Step 1: Update rpc_preview_max_charge to accept explicit p_app_count parameter
CREATE OR REPLACE FUNCTION public.rpc_preview_max_charge(
    p_deadline_date date,
    p_limit_minutes integer,
    p_penalty_per_minute_cents integer,
    p_app_count integer,  -- NEW: Explicit app count parameter (single source of truth)
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

-- Update grants for new function signature
DROP FUNCTION IF EXISTS public.rpc_preview_max_charge(date, integer, integer, jsonb);
GRANT EXECUTE ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, integer, jsonb) TO authenticated, anon;

-- Update comment
COMMENT ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, integer, jsonb) IS 
'Preview the max charge amount before creating a commitment.
Uses explicit p_app_count parameter (single source of truth from client).
Returns the same value that would be stored in max_charge_cents when committing.
Call this from the frontend to display the authorization amount to the user.';

-- Step 2: Update rpc_create_commitment to accept explicit p_app_count parameter
CREATE OR REPLACE FUNCTION public.rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_app_count integer,  -- NEW: Explicit app count parameter (single source of truth)
  p_apps_to_limit jsonb,  -- Keep for storage in commitments table
  p_saved_payment_method_id text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_pm boolean;
  v_commitment_start_date date;
  v_deadline_ts timestamptz;
  v_max_charge_cents integer;
  v_commitment_id uuid;
  v_result json;
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
  v_deadline_ts := (p_deadline_date::timestamp AT TIME ZONE 'America/New_York') + INTERVAL '12 hours';

  -- 4) Use explicit p_app_count parameter (single source of truth from client)
  -- No longer extracting from JSONB arrays to avoid discrepancies

  -- 5) Calculate max charge using the SINGLE SOURCE OF TRUTH function
  -- This ensures preview and commitment creation use the exact same formula
  v_max_charge_cents := public.calculate_max_charge_cents(
    v_deadline_ts,
    p_limit_minutes,
    p_penalty_per_minute_cents,
    p_app_count  -- Use explicit parameter
  );

  -- 6) Ensure weekly_pools entry exists (create or update to open if exists)
  INSERT INTO public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  values (
    p_deadline_date,
    p_deadline_date,
    0,
    'open'
  )
  ON CONFLICT (week_start_date) DO UPDATE SET
    status = 'open',
    week_end_date = p_deadline_date;

  -- 7) Create commitment
  INSERT INTO public.commitments (
    user_id,
    week_start_date,
    week_end_date,
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
    p_deadline_date,
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

-- Update comment
COMMENT ON FUNCTION public.rpc_create_commitment(date, integer, integer, integer, jsonb, text) IS 
'Creates a new commitment for the authenticated user.
Uses explicit p_app_count parameter (single source of truth from client).
Uses calculate_max_charge_cents() for the max charge calculation (single source of truth).
This ensures preview and commitment creation use the exact same formula and app count.';

