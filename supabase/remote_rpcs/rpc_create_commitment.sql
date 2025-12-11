-- ==============================================================================
-- RPC Function: rpc_create_commitment
-- ==============================================================================
-- Creates a new commitment for the authenticated user.
-- Uses calculate_max_charge_cents() for the max charge calculation (single source of truth).
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_apps_to_limit jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_pm boolean;
  v_commitment_start_date date;
  v_deadline_ts timestamptz;
  v_app_count integer;
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

  -- 4) Count apps
  v_app_count := COALESCE(jsonb_array_length(p_apps_to_limit->'app_bundle_ids'), 0)
               + COALESCE(jsonb_array_length(p_apps_to_limit->'categories'), 0);

  -- 5) Calculate max charge using the SINGLE SOURCE OF TRUTH function
  v_max_charge_cents := public.calculate_max_charge_cents(
    v_deadline_ts,
    p_limit_minutes,
    p_penalty_per_minute_cents,
    v_app_count
  );

  -- 6) Ensure weekly_pools entry exists
  INSERT INTO public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  VALUES (
    p_deadline_date,
    p_deadline_date,
    0,
    'open'
  )
  ON CONFLICT (week_start_date) DO NOTHING;

  -- 7) Insert commitment
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
    created_at
  )
  VALUES (
    v_user_id,
    v_commitment_start_date,
    p_deadline_date,
    p_limit_minutes,
    p_penalty_per_minute_cents,
    p_apps_to_limit,
    'pending',
    'ok',
    NULL,
    NOW(),
    v_max_charge_cents,
    NOW()
  )
  RETURNING id INTO v_commitment_id;

  -- 8) Return the created commitment as JSON
  SELECT row_to_json(c.*) INTO v_result
  FROM public.commitments c
  WHERE c.id = v_commitment_id;

  RETURN v_result;
END;
$$;
