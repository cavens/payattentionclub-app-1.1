--
-- PostgreSQL database dump
--

\restrict 4SxJtsyILKGc4TuZqCyRX9liDc256r2UEhA74iDwoaJi7aaZBUZYEQc1rNnO4tT

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: call_weekly_close(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.call_weekly_close() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  request_id bigint;
BEGIN
  -- Make HTTP POST request to weekly-close Edge Function
  SELECT net.http_post(
    'https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/weekly-close',  -- Staging project URL
    jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    '{}'::jsonb,
    30000  -- 30 second timeout
  ) INTO request_id;
  
  -- Log that request was queued
  RAISE NOTICE 'Weekly close Edge Function called. Request ID: %', request_id;
  
  -- Note: pg_net processes requests asynchronously
  -- The response will be available in net.http_response_queue later
  -- For cron jobs, we just need to trigger the request
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error calling weekly-close Edge Function: %', SQLERRM;
END;
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.users (id, email, created_at)
  VALUES (NEW.id, NEW.email, NOW())
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;


--
-- Name: rpc_create_commitment(date, integer, integer, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_create_commitment(p_deadline_date date, p_limit_minutes integer, p_penalty_per_minute_cents integer, p_apps_to_limit jsonb) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_has_pm boolean;
  v_commitment_start_date date;
  v_deadline_ts timestamptz;
  v_minutes_remaining numeric;
  v_potential_overage numeric;
  v_risk_factor numeric;
  v_max_charge_cents integer;
  v_app_count integer;
  v_commitment_id uuid;
  v_result json;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select u.has_active_payment_method
    into v_has_pm
    from public.users u
    where u.id = v_user_id;

  if coalesce(v_has_pm, false) = false then
    raise exception 'User has no active payment method' using errcode = 'P0001';
  end if;

  v_commitment_start_date := current_date;
  v_deadline_ts := (p_deadline_date::timestamp at time zone 'America/New_York') + interval '12 hours';

  v_minutes_remaining := greatest(
    0,
    extract(epoch from (v_deadline_ts - now())) / 60.0
  );

  v_app_count := coalesce(jsonb_array_length(p_apps_to_limit->'app_bundle_ids'), 0)
               + coalesce(jsonb_array_length(p_apps_to_limit->'categories'), 0);

  v_risk_factor := 1.0 + 0.1 * v_app_count;

  v_potential_overage := greatest(0, v_minutes_remaining - p_limit_minutes);

  v_max_charge_cents :=
      v_potential_overage
    * p_penalty_per_minute_cents
    * v_risk_factor;

  if v_minutes_remaining > 0 then
    v_max_charge_cents := greatest(500, floor(v_max_charge_cents)::int);
  else
    v_max_charge_cents := 0;
  end if;

  insert into public.weekly_pools (
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
  on conflict (week_start_date) do nothing;

  insert into public.commitments (
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
    now()
  )
  returning id into v_commitment_id;

  select row_to_json(c.*) into v_result
  from public.commitments c
  where c.id = v_commitment_id;

  return v_result;
end;
$$;


--
-- Name: rpc_get_week_status(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_get_week_status(p_week_start_date date DEFAULT NULL::date) RETURNS TABLE(user_total_penalty_cents integer, user_status text, user_max_charge_cents integer, pool_total_penalty_cents integer, pool_status text, pool_instagram_post_url text, pool_instagram_image_url text, user_settlement_status text, charged_amount_cents integer, actual_amount_cents integer, refund_amount_cents integer, needs_reconciliation boolean, reconciliation_delta_cents integer, reconciliation_reason text, reconciliation_detected_at timestamp with time zone, week_grace_expires_at timestamp with time zone, week_end_date timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_week_deadline date;
  v_commitment public.commitments;
  v_user_week_pen public.user_week_penalties;
  v_pool public.weekly_pools;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_week_start_date is not null then
    v_week_deadline := p_week_start_date;
  else
    v_week_deadline := current_date + (8 - extract(dow from current_date)::int) % 7;
    if extract(dow from current_date) = 1 then
      v_week_deadline := current_date + 7;
    end if;
  end if;

  select c.*
    into v_commitment
    from public.commitments c
    where c.user_id = v_user_id
      and c.week_end_date = v_week_deadline
    order by c.created_at desc
    limit 1;

  select uwp.*
    into v_user_week_pen
    from public.user_week_penalties uwp
    where uwp.user_id = v_user_id
      and uwp.week_start_date = v_week_deadline
    limit 1;

  select wp.*
    into v_pool
    from public.weekly_pools wp
    where wp.week_start_date = v_week_deadline
    limit 1;

  user_total_penalty_cents := coalesce(v_user_week_pen.total_penalty_cents, 0);
  user_status := coalesce(v_user_week_pen.status, 'none');
  user_max_charge_cents := coalesce(v_commitment.max_charge_cents, 0);
  pool_total_penalty_cents := coalesce(v_pool.total_penalty_cents, 0);
  pool_status := coalesce(v_pool.status, 'open');
  pool_instagram_post_url := v_pool.instagram_post_url;
  pool_instagram_image_url := v_pool.instagram_image_url;

  user_settlement_status := coalesce(v_user_week_pen.settlement_status, 'pending');
  charged_amount_cents := coalesce(v_user_week_pen.charged_amount_cents, 0);
  actual_amount_cents := coalesce(v_user_week_pen.actual_amount_cents, v_user_week_pen.total_penalty_cents, 0);
  refund_amount_cents := coalesce(v_user_week_pen.refund_amount_cents, 0);
  needs_reconciliation := coalesce(v_user_week_pen.needs_reconciliation, false);
  reconciliation_delta_cents := coalesce(v_user_week_pen.reconciliation_delta_cents, 0);
  reconciliation_reason := v_user_week_pen.reconciliation_reason;
  reconciliation_detected_at := v_user_week_pen.reconciliation_detected_at;

  -- Convert week deadline + grace to Monday/Tuesday 12:00 PM ET
  week_end_date := (v_week_deadline::timestamptz at time zone 'America/New_York')
                   at time zone 'UTC'
                   + interval '12 hours';
  week_grace_expires_at :=
    coalesce(
      v_commitment.week_grace_expires_at,
      week_end_date + interval '24 hours'
    );

  return next;
  return;
end;
$$;


--
-- Name: rpc_report_usage(date, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_report_usage(p_date date, p_week_start_date date, p_used_minutes integer) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_commitment_id uuid;
  v_limit_minutes integer;
  v_penalty_per_minute_cents integer;
  v_exceeded_minutes integer;
  v_penalty_cents integer;
  v_user_week_total_cents integer;
  v_pool_total_cents integer;
  v_result json;
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Find the active commitment for this user and week
  -- FIX: Match by week_end_date (deadline), not week_start_date
  -- Note: week_end_date in commitments table is actually the deadline (next Monday)
  -- So we match where the deadline (week_end_date) equals p_week_start_date
  SELECT 
    c.id,
    c.limit_minutes,
    c.penalty_per_minute_cents
  INTO 
    v_commitment_id,
    v_limit_minutes,
    v_penalty_per_minute_cents
  FROM public.commitments c
  WHERE c.user_id = v_user_id
    AND c.week_end_date = p_week_start_date  -- FIX: Changed from week_start_date to week_end_date
    AND c.status IN ('pending', 'active')
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- 3) Check if commitment exists
  IF v_commitment_id IS NULL THEN
    RAISE EXCEPTION 'No active commitment found for this week' USING ERRCODE = 'P0002';
  END IF;

  -- 4) Calculate exceeded minutes and penalty
  v_exceeded_minutes := GREATEST(0, p_used_minutes - v_limit_minutes);
  v_penalty_cents := v_exceeded_minutes * v_penalty_per_minute_cents;

  -- 5) Upsert into daily_usage
  INSERT INTO public.daily_usage (
    user_id,
    commitment_id,
    date,
    used_minutes,
    limit_minutes,
    exceeded_minutes,
    penalty_cents,
    is_estimated,
    reported_at,
    source
  )
  VALUES (
    v_user_id,
    v_commitment_id,
    p_date,
    p_used_minutes,
    v_limit_minutes,
    v_exceeded_minutes,
    v_penalty_cents,
    false,
    NOW(),
    'ios_app'
  )
  ON CONFLICT (user_id, date, commitment_id)
  DO UPDATE SET
    used_minutes = EXCLUDED.used_minutes,
    limit_minutes = EXCLUDED.limit_minutes,
    exceeded_minutes = EXCLUDED.exceeded_minutes,
    penalty_cents = EXCLUDED.penalty_cents,
    is_estimated = EXCLUDED.is_estimated,
    reported_at = NOW(),
    source = EXCLUDED.source;

  -- 6) Recalculate user_week_penalties
  -- Sum all daily usage for this commitment (from commitment start to deadline)
  SELECT COALESCE(SUM(penalty_cents), 0)
  INTO v_user_week_total_cents
  FROM public.daily_usage
  WHERE user_id = v_user_id
    AND commitment_id = v_commitment_id
    AND date >= (
      SELECT week_start_date  -- Actually the commitment start date
      FROM public.commitments 
      WHERE id = v_commitment_id
    )
    AND date <= (
      SELECT week_end_date  -- Actually the deadline
      FROM public.commitments 
      WHERE id = v_commitment_id
    );

  -- Upsert user_week_penalties
  INSERT INTO public.user_week_penalties (
    user_id,
    week_start_date,  -- Actually stores the deadline
    total_penalty_cents,
    status,
    last_updated
  )
  VALUES (
    v_user_id,
    p_week_start_date,  -- Deadline (next Monday)
    v_user_week_total_cents,
    'pending',
    NOW()
  )
  ON CONFLICT (user_id, week_start_date)
  DO UPDATE SET
    total_penalty_cents = EXCLUDED.total_penalty_cents,
    last_updated = NOW();

  -- 7) Recalculate weekly_pools
  -- FIX: Changed from UPDATE to INSERT ... ON CONFLICT to create if missing
  -- Note: In weekly_pools, week_start_date is the deadline (Monday before noon)
  -- All users with the same deadline share the same pool
  SELECT COALESCE(SUM(total_penalty_cents), 0)
  INTO v_pool_total_cents
  FROM public.user_week_penalties
  WHERE week_start_date = p_week_start_date;

  -- Upsert weekly_pools (creates if doesn't exist, updates if exists)
  INSERT INTO public.weekly_pools (
    week_start_date,  -- Deadline (next Monday) - used as pool identifier
    week_end_date,    -- Same as start (deadline is the pool identifier)
    total_penalty_cents,
    status
  )
  VALUES (
    p_week_start_date,  -- Deadline (next Monday)
    p_week_start_date,  -- Same as start (deadline is the pool identifier)
    v_pool_total_cents,
    'open'
  )
  ON CONFLICT (week_start_date)  -- FIX: Changed from UPDATE to INSERT ... ON CONFLICT
  DO UPDATE SET
    total_penalty_cents = EXCLUDED.total_penalty_cents;

  -- 8) Return result as JSON
  -- FIX: Changed from RETURN; to RETURN json_build_object(...)
  SELECT json_build_object(
    'date', p_date::text,
    'limit_minutes', v_limit_minutes,
    'used_minutes', p_used_minutes,
    'exceeded_minutes', v_exceeded_minutes,
    'penalty_cents', v_penalty_cents,
    'user_week_total_cents', v_user_week_total_cents,
    'pool_total_cents', v_pool_total_cents
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


--
-- Name: rpc_setup_test_data(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_setup_test_data() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_real_user_id uuid;
  v_test_user_1_id uuid := '11111111-1111-1111-1111-111111111111'::uuid;
  v_test_user_2_id uuid := '22222222-2222-2222-2222-222222222222'::uuid;
  v_test_user_3_id uuid := '33333333-3333-3333-3333-333333333333'::uuid;
  v_commitment_1_id uuid;
  v_commitment_2_id uuid;
  v_commitment_3_id uuid;
  v_deadline_date date;
  v_start_date date;
  v_result json;
BEGIN
  -- Calculate deadline to match weekly-close logic
  -- If today is Monday, use today (week ending today)
  -- If today is Sunday, use tomorrow (next Monday)
  -- Otherwise, use last Monday (go back to Monday)
  IF EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN
    -- Today is Monday - use today (week ending today)
    v_deadline_date := CURRENT_DATE;
  ELSIF EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN
    -- Today is Sunday - use tomorrow (next Monday)
    v_deadline_date := CURRENT_DATE + 1;
  ELSE
    -- Today is Tue-Sat - go back to last Monday
    v_deadline_date := CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1);
  END IF;
  v_start_date := CURRENT_DATE;

  -- 1) Set up real user with Stripe customer ID
  -- First, try to find existing user by email
  SELECT id INTO v_real_user_id
  FROM auth.users
  WHERE email = 'jef+stripe@cavens.io'
  LIMIT 1;

  -- If user doesn't exist in auth.users, we can't create it (needs Sign in with Apple)
  -- So we'll update public.users if the auth user exists
  IF v_real_user_id IS NOT NULL THEN
    INSERT INTO public.users (
      id,
      email,
      stripe_customer_id,
      has_active_payment_method,
      is_test_user,
      created_at
    )
    VALUES (
      v_real_user_id,
      'jef+stripe@cavens.io',
      'cus_TRROpBSIbBGe2M',
      true,
      true,
      NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      stripe_customer_id = 'cus_TRROpBSIbBGe2M',
      has_active_payment_method = true,
      is_test_user = true;
  END IF;

  -- 2) Create/update test users (these won't have auth.users entries, but we'll create public.users entries)
  -- Test User 1: Has penalties, will be charged - USING REAL STRIPE CUSTOMER ID FOR TESTING
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at
  )
  VALUES (
    v_test_user_1_id,
    'test-user-1@example.com',
    'cus_TRROpBSIbBGe2M',  -- Using real Stripe customer ID for testing
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = 'cus_TRROpBSIbBGe2M',  -- Using real Stripe customer ID for testing
    has_active_payment_method = true,
    is_test_user = true;

  -- Test User 2: Has penalties, will be charged
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at
  )
  VALUES (
    v_test_user_2_id,
    'test-user-2@example.com',
    'cus_test_user_2',
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user;

  -- Test User 3: No penalties (stayed within limit)
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at
  )
  VALUES (
    v_test_user_3_id,
    'test-user-3@example.com',
    'cus_test_user_3',
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user;

  -- 3) Create weekly pool for this week
  INSERT INTO public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  VALUES (
    v_deadline_date,
    v_deadline_date,
    0,
    'open'
  )
  ON CONFLICT (week_start_date) DO UPDATE SET
    status = 'open',
    total_penalty_cents = 0;

  -- 4) Create commitments
  -- Commitment 1: Real user - exceeded limit (will have penalties)
  IF v_real_user_id IS NOT NULL THEN
    INSERT INTO public.commitments (
      id,
      user_id,
      week_start_date,
      week_end_date,
      limit_minutes,
      penalty_per_minute_cents,
      apps_to_limit,
      status,
      monitoring_status,
      max_charge_cents,
      created_at
    )
    VALUES (
      gen_random_uuid(),
      v_real_user_id,
      v_start_date,
      v_deadline_date,
      60,  -- 60 minute limit
      10,  -- 10 cents per minute penalty
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      4200,  -- max charge
      NOW()
    )
    RETURNING id INTO v_commitment_1_id;
  END IF;

  -- Commitment 2: Test User 1 - exceeded limit
  INSERT INTO public.commitments (
    id,
    user_id,
    week_start_date,
    week_end_date,
    limit_minutes,
    penalty_per_minute_cents,
    apps_to_limit,
    status,
    monitoring_status,
    max_charge_cents,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_test_user_1_id,
    v_start_date,
    v_deadline_date,
    120,  -- 120 minute limit
      5,  -- 5 cents per minute penalty
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      6000,  -- max charge
      NOW()
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_commitment_2_id;

  -- Get commitment ID if it already exists
  IF v_commitment_2_id IS NULL THEN
    SELECT id INTO v_commitment_2_id
    FROM public.commitments
    WHERE user_id = v_test_user_1_id
      AND week_end_date = v_deadline_date
    LIMIT 1;
  END IF;

  -- Commitment 3: Test User 3 - stayed within limit
  INSERT INTO public.commitments (
    id,
    user_id,
    week_start_date,
    week_end_date,
    limit_minutes,
    penalty_per_minute_cents,
    apps_to_limit,
    status,
    monitoring_status,
    max_charge_cents,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_test_user_3_id,
    v_start_date,
    v_deadline_date,
    180,  -- 180 minute limit
      3,  -- 3 cents per minute penalty
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      5400,  -- max charge
      NOW()
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_commitment_3_id;

  -- Get commitment ID if it already exists
  IF v_commitment_3_id IS NULL THEN
    SELECT id INTO v_commitment_3_id
    FROM public.commitments
    WHERE user_id = v_test_user_3_id
      AND week_end_date = v_deadline_date
    LIMIT 1;
  END IF;

  -- 5) Create daily_usage data
  -- Real user: Exceeded limit on 3 days (30 minutes over each day = 90 minutes total)
  IF v_real_user_id IS NOT NULL AND v_commitment_1_id IS NOT NULL THEN
    -- Day 1: Used 90 minutes (30 over limit)
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_real_user_id,
      v_commitment_1_id,
      v_start_date,
      90,  -- used
      60,  -- limit
      30,  -- exceeded
      300, -- penalty (30 * 10 cents)
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;

    -- Day 2: Used 90 minutes (30 over limit)
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_real_user_id,
      v_commitment_1_id,
      v_start_date + 1,
      90,
      60,
      30,
      300,
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;

    -- Day 3: Used 90 minutes (30 over limit)
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_real_user_id,
      v_commitment_1_id,
      v_start_date + 2,
      90,
      60,
      30,
      300,
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

  -- Test User 1: Exceeded limit (used 150 minutes, limit 120, exceeded 30)
  IF v_commitment_2_id IS NOT NULL THEN
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_test_user_1_id,
      v_commitment_2_id,
      v_start_date,
      150,
      120,
      30,
      150,  -- 30 * 5 cents
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

  -- Test User 3: Stayed within limit (used 100 minutes, limit 180, exceeded 0)
  IF v_commitment_3_id IS NOT NULL THEN
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_test_user_3_id,
      v_commitment_3_id,
      v_start_date,
      100,
      180,
      0,
      0,  -- No penalty
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

  -- 6) Return summary
  SELECT json_build_object(
    'success', true,
    'message', 'Test data setup complete',
    'deadline_date', v_deadline_date,
    'real_user_id', v_real_user_id,
    'real_user_stripe_customer', 'cus_TRROpBSIbBGe2M',
    'test_users_created', 3,
    'commitments_created', CASE WHEN v_real_user_id IS NOT NULL THEN 3 ELSE 2 END,
    'daily_usage_entries', CASE WHEN v_real_user_id IS NOT NULL THEN 4 ELSE 2 END
  ) INTO v_result;

  RETURN v_result;
END;
$$;


--
-- Name: rpc_setup_test_data(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_setup_test_data(p_real_user_email text DEFAULT 'jef+stripe@cavens.io'::text, p_real_user_stripe_customer text DEFAULT 'cus_TRROpBSIbBGe2M'::text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_real_user_id uuid;
  v_seed_real_user_id uuid := '44444444-4444-4444-4444-444444444444'::uuid;
  v_real_user_email text := coalesce(nullif(p_real_user_email, ''), 'jef+stripe@cavens.io');
  v_real_user_stripe_customer text := coalesce(nullif(p_real_user_stripe_customer, ''), 'cus_TRROpBSIbBGe2M');
  v_test_user_1_id uuid := '11111111-1111-1111-1111-111111111111'::uuid;
  v_test_user_2_id uuid := '22222222-2222-2222-2222-222222222222'::uuid;
  v_test_user_3_id uuid := '33333333-3333-3333-3333-333333333333'::uuid;
  v_commitment_1_id uuid;
  v_commitment_2_id uuid;
  v_commitment_3_id uuid;
  v_deadline_date date;
  v_start_date date;
  v_result json;
BEGIN
  -- Calculate deadline to match weekly-close logic
  -- If today is Monday, use today (week ending today)
  -- If today is Sunday, use tomorrow (next Monday)
  -- Otherwise, use last Monday (go back to Monday)
  IF EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN
    -- Today is Monday - use today (week ending today)
    v_deadline_date := CURRENT_DATE;
  ELSIF EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN
    -- Today is Sunday - use tomorrow (next Monday)
    v_deadline_date := CURRENT_DATE + 1;
  ELSE
    -- Today is Tue-Sat - go back to last Monday
    v_deadline_date := CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1);
  END IF;
  v_start_date := CURRENT_DATE;

  -- 1) Set up real user with Stripe customer ID
  -- First, try to find existing user by email
  SELECT id INTO v_real_user_id
  FROM auth.users
  WHERE email = v_real_user_email
  LIMIT 1;

  IF v_real_user_id IS NULL THEN
    v_real_user_id := v_seed_real_user_id;
  END IF;

  -- If user doesn't exist in auth.users, we can't create it (needs Sign in with Apple)
  -- So we'll update public.users if the auth user exists
  IF v_real_user_id IS NOT NULL THEN
    INSERT INTO public.users (
      id,
      email,
      stripe_customer_id,
      has_active_payment_method,
      is_test_user,
      created_at
    )
    VALUES (
      v_real_user_id,
      v_real_user_email,
      v_real_user_stripe_customer,
      true,
      true,
      NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      stripe_customer_id = v_real_user_stripe_customer,
      has_active_payment_method = true,
      is_test_user = true;
  END IF;

  -- 2) Create/update test users (these won't have auth.users entries, but we'll create public.users entries)
  -- Test User 1: Has penalties, will be charged - USING REAL STRIPE CUSTOMER ID FOR TESTING
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at
  )
  VALUES (
    v_test_user_1_id,
    'test-user-1@example.com',
    v_real_user_stripe_customer,  -- Using real Stripe customer ID for testing
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = v_real_user_stripe_customer,  -- Using real Stripe customer ID for testing
    has_active_payment_method = true,
    is_test_user = true;

  -- Test User 2: Has penalties, will be charged
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at
  )
  VALUES (
    v_test_user_2_id,
    'test-user-2@example.com',
    'cus_test_user_2',
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user;

  -- Test User 3: No penalties (stayed within limit)
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at
  )
  VALUES (
    v_test_user_3_id,
    'test-user-3@example.com',
    'cus_test_user_3',
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user;

  -- 3) Create weekly pool for this week
  INSERT INTO public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  VALUES (
    v_deadline_date,
    v_deadline_date,
    0,
    'open'
  )
  ON CONFLICT (week_start_date) DO UPDATE SET
    status = 'open',
    total_penalty_cents = 0;

  -- 4) Create commitments
  -- Commitment 1: Real user - exceeded limit (will have penalties)
  IF v_real_user_id IS NOT NULL THEN
    INSERT INTO public.commitments (
      id,
      user_id,
      week_start_date,
      week_end_date,
      limit_minutes,
      penalty_per_minute_cents,
      apps_to_limit,
      status,
      monitoring_status,
      max_charge_cents,
      created_at
    )
    VALUES (
      gen_random_uuid(),
      v_real_user_id,
      v_start_date,
      v_deadline_date,
      60,  -- 60 minute limit
      10,  -- 10 cents per minute penalty
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      4200,  -- max charge
      NOW()
    )
    RETURNING id INTO v_commitment_1_id;
  END IF;

  -- Commitment 2: Test User 1 - exceeded limit
  INSERT INTO public.commitments (
    id,
    user_id,
    week_start_date,
    week_end_date,
    limit_minutes,
    penalty_per_minute_cents,
    apps_to_limit,
    status,
    monitoring_status,
    max_charge_cents,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_test_user_1_id,
    v_start_date,
    v_deadline_date,
    120,  -- 120 minute limit
      5,  -- 5 cents per minute penalty
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      6000,  -- max charge
      NOW()
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_commitment_2_id;

  -- Get commitment ID if it already exists
  IF v_commitment_2_id IS NULL THEN
    SELECT id INTO v_commitment_2_id
    FROM public.commitments
    WHERE user_id = v_test_user_1_id
      AND week_end_date = v_deadline_date
    LIMIT 1;
  END IF;

  -- Commitment 3: Test User 3 - stayed within limit
  INSERT INTO public.commitments (
    id,
    user_id,
    week_start_date,
    week_end_date,
    limit_minutes,
    penalty_per_minute_cents,
    apps_to_limit,
    status,
    monitoring_status,
    max_charge_cents,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_test_user_3_id,
    v_start_date,
    v_deadline_date,
    180,  -- 180 minute limit
      3,  -- 3 cents per minute penalty
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      5400,  -- max charge
      NOW()
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_commitment_3_id;

  -- Get commitment ID if it already exists
  IF v_commitment_3_id IS NULL THEN
    SELECT id INTO v_commitment_3_id
    FROM public.commitments
    WHERE user_id = v_test_user_3_id
      AND week_end_date = v_deadline_date
    LIMIT 1;
  END IF;

  -- 5) Create daily_usage data
  -- Real user: Exceeded limit on 3 days (30 minutes over each day = 90 minutes total)
  IF v_real_user_id IS NOT NULL AND v_commitment_1_id IS NOT NULL THEN
    -- Day 1: Used 90 minutes (30 over limit)
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_real_user_id,
      v_commitment_1_id,
      v_start_date,
      90,  -- used
      60,  -- limit
      30,  -- exceeded
      300, -- penalty (30 * 10 cents)
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;

    -- Day 2: Used 90 minutes (30 over limit)
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_real_user_id,
      v_commitment_1_id,
      v_start_date + 1,
      90,
      60,
      30,
      300,
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;

    -- Day 3: Used 90 minutes (30 over limit)
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_real_user_id,
      v_commitment_1_id,
      v_start_date + 2,
      90,
      60,
      30,
      300,
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

  -- Test User 1: Exceeded limit (used 150 minutes, limit 120, exceeded 30)
  IF v_commitment_2_id IS NOT NULL THEN
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_test_user_1_id,
      v_commitment_2_id,
      v_start_date,
      150,
      120,
      30,
      150,  -- 30 * 5 cents
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

  -- Test User 3: Stayed within limit (used 100 minutes, limit 180, exceeded 0)
  IF v_commitment_3_id IS NOT NULL THEN
    INSERT INTO public.daily_usage (
      user_id,
      commitment_id,
      date,
      used_minutes,
      limit_minutes,
      exceeded_minutes,
      penalty_cents,
      is_estimated,
      reported_at
    )
    VALUES (
      v_test_user_3_id,
      v_commitment_3_id,
      v_start_date,
      100,
      180,
      0,
      0,  -- No penalty
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

  -- 6) Return summary
  SELECT json_build_object(
    'success', true,
    'message', 'Test data setup complete',
    'deadline_date', v_deadline_date,
    'real_user_id', v_real_user_id,
    'real_user_stripe_customer', v_real_user_stripe_customer,
    'test_users_created', 3,
    'commitments_created', CASE WHEN v_real_user_id IS NOT NULL THEN 3 ELSE 2 END,
    'daily_usage_entries', CASE WHEN v_real_user_id IS NOT NULL THEN 4 ELSE 2 END
  ) INTO v_result;

  RETURN v_result;
END;
$$;


--
-- Name: rpc_sync_daily_usage(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rpc_sync_daily_usage(p_entries jsonb) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_entry jsonb;
  v_date date;
  v_week_start_date date;
  v_used_minutes integer;
  v_commitment_id uuid;
  v_limit_minutes integer;
  v_penalty_per_minute_cents integer;
  v_exceeded_minutes integer;
  v_penalty_cents integer;
  v_synced_dates text[] := ARRAY[]::text[];
  v_failed_dates text[] := ARRAY[]::text[];
  v_errors text[] := ARRAY[]::text[];
  v_user_week_total_cents integer;
  v_pool_total_cents integer;
  v_result json;
  v_processed_weeks date[] := ARRAY[]::date[];
  v_week date;
  v_prev_settlement_status text;
  v_prev_charged_amount integer;
  v_needs_reconciliation boolean;
  v_reconciliation_delta integer;
  V_SETTLED_STATUSES CONSTANT text[] := ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial'];
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Validate input is an array
  IF jsonb_typeof(p_entries) != 'array' THEN
    RAISE EXCEPTION 'p_entries must be a JSON array' USING ERRCODE = '22023';
  END IF;

  -- 3) Process each entry
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    BEGIN
      -- Extract entry fields
      v_date := (v_entry->>'date')::date;
      v_week_start_date := (v_entry->>'week_start_date')::date;
      v_used_minutes := (v_entry->>'used_minutes')::integer;

      -- Validate required fields
      IF v_date IS NULL OR v_week_start_date IS NULL OR v_used_minutes IS NULL THEN
        v_failed_dates := array_append(v_failed_dates, COALESCE(v_entry->>'date', 'unknown'));
        v_errors := array_append(v_errors, format('Invalid entry: missing required fields'));
        CONTINUE;
      END IF;

      -- Find the active commitment for this user and week
      SELECT 
        c.id,
        c.limit_minutes,
        c.penalty_per_minute_cents
      INTO 
        v_commitment_id,
        v_limit_minutes,
        v_penalty_per_minute_cents
      FROM public.commitments c
      WHERE c.user_id = v_user_id
        AND c.week_end_date = v_week_start_date  -- Match by deadline (week_end_date)
        AND c.status IN ('pending', 'active')
      ORDER BY c.created_at DESC
      LIMIT 1;

      -- Check if commitment exists
      IF v_commitment_id IS NULL THEN
        v_failed_dates := array_append(v_failed_dates, v_date::text);
        v_errors := array_append(v_errors, format('No active commitment found for week %s', v_week_start_date::text));
        CONTINUE;
      END IF;

      -- Calculate exceeded minutes and penalty
      v_exceeded_minutes := GREATEST(0, v_used_minutes - v_limit_minutes);
      v_penalty_cents := v_exceeded_minutes * v_penalty_per_minute_cents;

      -- Upsert into daily_usage
      INSERT INTO public.daily_usage (
        user_id,
        commitment_id,
        date,
        used_minutes,
        limit_minutes,
        exceeded_minutes,
        penalty_cents,
        is_estimated,
        reported_at,
        source
      )
      VALUES (
        v_user_id,
        v_commitment_id,
        v_date,
        v_used_minutes,
        v_limit_minutes,
        v_exceeded_minutes,
        v_penalty_cents,
        false,
        NOW(),
        'ios_app'
      )
      ON CONFLICT (user_id, date, commitment_id)
      DO UPDATE SET
        used_minutes = EXCLUDED.used_minutes,
        limit_minutes = EXCLUDED.limit_minutes,
        exceeded_minutes = EXCLUDED.exceeded_minutes,
        penalty_cents = EXCLUDED.penalty_cents,
        is_estimated = EXCLUDED.is_estimated,
        reported_at = NOW(),
        source = EXCLUDED.source;

      -- Track this week for recalculation (avoid duplicates)
      IF NOT (v_week_start_date = ANY(v_processed_weeks)) THEN
        v_processed_weeks := array_append(v_processed_weeks, v_week_start_date);
      END IF;

      -- Mark as successfully synced
      v_synced_dates := array_append(v_synced_dates, v_date::text);

    EXCEPTION
      WHEN OTHERS THEN
        -- Log error and continue with next entry
        v_failed_dates := array_append(v_failed_dates, COALESCE(v_date::text, 'unknown'));
        v_errors := array_append(v_errors, format('Error processing %s: %s', COALESCE(v_date::text, 'unknown'), SQLERRM));
    END;
  END LOOP;

  -- 4) Recalculate weekly totals for each unique week that was processed
  FOREACH v_week IN ARRAY v_processed_weeks
  LOOP
    BEGIN
      -- Recalculate user_week_penalties for this week
      SELECT COALESCE(SUM(penalty_cents), 0)
      INTO v_user_week_total_cents
      FROM public.daily_usage du
      JOIN public.commitments c ON du.commitment_id = c.id
      WHERE du.user_id = v_user_id
        AND c.week_end_date = v_week  -- Match by deadline
        AND du.date >= c.week_start_date
        AND du.date <= c.week_end_date;

      -- Load any previous settlement metadata (if it exists)
      v_prev_settlement_status := NULL;
      v_prev_charged_amount := 0;
      BEGIN
        SELECT settlement_status, COALESCE(charged_amount_cents, 0)
        INTO v_prev_settlement_status, v_prev_charged_amount
        FROM public.user_week_penalties
        WHERE user_id = v_user_id
          AND week_start_date = v_week;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_prev_settlement_status := NULL;
          v_prev_charged_amount := 0;
      END;

      v_needs_reconciliation := false;
      v_reconciliation_delta := 0;
      IF v_prev_settlement_status = ANY(V_SETTLED_STATUSES) THEN
        v_reconciliation_delta := v_user_week_total_cents - COALESCE(v_prev_charged_amount, 0);
        IF v_reconciliation_delta <> 0 THEN
          v_needs_reconciliation := true;
        END IF;
      END IF;

      -- Upsert user_week_penalties with reconciliation flags
      INSERT INTO public.user_week_penalties (
        user_id,
        week_start_date,  -- Actually stores the Monday deadline
        total_penalty_cents,
        status,
        settlement_status,
        actual_amount_cents,
        needs_reconciliation,
        reconciliation_delta_cents,
        reconciliation_reason,
        reconciliation_detected_at,
        last_updated
      )
      VALUES (
        v_user_id,
        v_week,
        v_user_week_total_cents,
        'pending',
        COALESCE(v_prev_settlement_status, 'pending'),
        v_user_week_total_cents,
        v_needs_reconciliation,
        CASE WHEN v_needs_reconciliation THEN v_reconciliation_delta ELSE 0 END,
        CASE WHEN v_needs_reconciliation THEN 'late_sync_delta' ELSE NULL END,
        CASE WHEN v_needs_reconciliation THEN NOW() ELSE NULL END,
        NOW()
      )
      ON CONFLICT (user_id, week_start_date)
      DO UPDATE SET
        total_penalty_cents = EXCLUDED.total_penalty_cents,
        actual_amount_cents = EXCLUDED.actual_amount_cents,
        needs_reconciliation = EXCLUDED.needs_reconciliation,
        reconciliation_delta_cents = EXCLUDED.reconciliation_delta_cents,
        reconciliation_reason = CASE
          WHEN EXCLUDED.needs_reconciliation THEN EXCLUDED.reconciliation_reason
          ELSE NULL
        END,
        reconciliation_detected_at = CASE
          WHEN EXCLUDED.needs_reconciliation AND public.user_week_penalties.needs_reconciliation = false
            THEN EXCLUDED.reconciliation_detected_at
          WHEN EXCLUDED.needs_reconciliation
            THEN COALESCE(public.user_week_penalties.reconciliation_detected_at, EXCLUDED.reconciliation_detected_at)
          ELSE NULL
        END,
        settlement_status = COALESCE(public.user_week_penalties.settlement_status, EXCLUDED.settlement_status),
        last_updated = NOW();

      -- Recalculate weekly_pools for this week
      SELECT COALESCE(SUM(total_penalty_cents), 0)
      INTO v_pool_total_cents
      FROM public.user_week_penalties
      WHERE week_start_date = v_week;

      -- Upsert weekly_pools
      INSERT INTO public.weekly_pools (
        week_start_date,  -- Deadline (next Monday) - used as pool identifier
        week_end_date,    -- Same as start (deadline is the pool identifier)
        total_penalty_cents,
        status
      )
      VALUES (
        v_week,
        v_week,
        v_pool_total_cents,
        'open'
      )
      ON CONFLICT (week_start_date)
      DO UPDATE SET
        total_penalty_cents = EXCLUDED.total_penalty_cents;

    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the entire sync
        v_errors := array_append(v_errors, format('Error recalculating totals for week %s: %s', v_week::text, SQLERRM));
    END;
  END LOOP;

  -- 5) Return result as JSON, including reconciliation metadata per processed week
  SELECT json_build_object(
    'synced_count', array_length(v_synced_dates, 1),
    'failed_count', array_length(v_failed_dates, 1),
    'synced_dates', v_synced_dates,
    'failed_dates', v_failed_dates,
    'errors', v_errors,
    'processed_weeks', COALESCE((
      SELECT json_agg(json_build_object(
        'week_end_date', uw.week_start_date,
        'total_penalty_cents', uw.total_penalty_cents,
        'needs_reconciliation', uw.needs_reconciliation,
        'reconciliation_delta_cents', uw.reconciliation_delta_cents
      ))
      FROM public.user_week_penalties uw
      WHERE uw.user_id = v_user_id
        AND (v_processed_weeks IS NOT NULL AND array_length(v_processed_weeks, 1) > 0)
        AND uw.week_start_date = ANY(v_processed_weeks)
    ), '[]'::json)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: commitments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commitments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    week_start_date date NOT NULL,
    week_end_date date NOT NULL,
    limit_minutes integer NOT NULL,
    penalty_per_minute_cents integer NOT NULL,
    apps_to_limit jsonb,
    status text DEFAULT 'pending'::text NOT NULL,
    monitoring_status text DEFAULT 'ok'::text NOT NULL,
    monitoring_revoked_at timestamp with time zone,
    autocharge_consent_at timestamp with time zone,
    max_charge_cents integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    saved_payment_method_id text,
    week_grace_expires_at timestamp with time zone
);


--
-- Name: daily_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    commitment_id uuid NOT NULL,
    date date NOT NULL,
    used_minutes integer NOT NULL,
    limit_minutes integer NOT NULL,
    exceeded_minutes integer NOT NULL,
    penalty_cents integer NOT NULL,
    is_estimated boolean DEFAULT false NOT NULL,
    reported_at timestamp with time zone DEFAULT now() NOT NULL,
    source text DEFAULT 'ios_app'::text NOT NULL
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    week_start_date date NOT NULL,
    amount_cents integer NOT NULL,
    currency text DEFAULT 'usd'::text NOT NULL,
    stripe_payment_intent_id text,
    stripe_charge_id text,
    status text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    payment_type text DEFAULT 'penalty'::text NOT NULL,
    related_payment_intent_id text
);


--
-- Name: usage_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_adjustments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    commitment_id uuid NOT NULL,
    date date,
    minutes_delta integer NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_week_penalties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_week_penalties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    week_start_date date NOT NULL,
    total_penalty_cents integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    last_updated timestamp with time zone DEFAULT now() NOT NULL,
    charge_payment_intent_id text,
    charged_amount_cents integer DEFAULT 0,
    charged_at timestamp with time zone,
    actual_amount_cents integer DEFAULT 0,
    refund_amount_cents integer DEFAULT 0,
    refund_payment_intent_id text,
    refund_issued_at timestamp with time zone,
    settlement_status text DEFAULT 'pending'::text NOT NULL,
    needs_reconciliation boolean DEFAULT false NOT NULL,
    reconciliation_delta_cents integer DEFAULT 0 NOT NULL,
    reconciliation_reason text,
    reconciliation_detected_at timestamp with time zone
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email text,
    stripe_customer_id text,
    has_active_payment_method boolean DEFAULT false NOT NULL,
    is_test_user boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: weekly_pools; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_pools (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    week_start_date date NOT NULL,
    week_end_date date NOT NULL,
    total_penalty_cents integer DEFAULT 0 NOT NULL,
    status text,
    closed_at timestamp with time zone,
    instagram_post_url text,
    instagram_image_url text,
    notes text
);


--
-- Name: commitments commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments
    ADD CONSTRAINT commitments_pkey PRIMARY KEY (id);


--
-- Name: daily_usage daily_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usage
    ADD CONSTRAINT daily_usage_pkey PRIMARY KEY (id);


--
-- Name: daily_usage daily_usage_user_date_commitment_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usage
    ADD CONSTRAINT daily_usage_user_date_commitment_unique UNIQUE (user_id, date, commitment_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: usage_adjustments usage_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_adjustments
    ADD CONSTRAINT usage_adjustments_pkey PRIMARY KEY (id);


--
-- Name: user_week_penalties user_week_penalties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_week_penalties
    ADD CONSTRAINT user_week_penalties_pkey PRIMARY KEY (id);


--
-- Name: user_week_penalties user_week_penalties_user_week_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_week_penalties
    ADD CONSTRAINT user_week_penalties_user_week_unique UNIQUE (user_id, week_start_date);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: weekly_pools weekly_pools_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_pools
    ADD CONSTRAINT weekly_pools_pkey PRIMARY KEY (id);


--
-- Name: weekly_pools weekly_pools_week_start_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_pools
    ADD CONSTRAINT weekly_pools_week_start_date_key UNIQUE (week_start_date);


--
-- Name: idx_commitments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_commitments_status ON public.commitments USING btree (status);


--
-- Name: idx_commitments_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_commitments_user_id ON public.commitments USING btree (user_id);


--
-- Name: idx_commitments_week_end_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_commitments_week_end_date ON public.commitments USING btree (week_end_date);


--
-- Name: idx_daily_usage_commitment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_usage_commitment_id ON public.daily_usage USING btree (commitment_id);


--
-- Name: idx_daily_usage_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_usage_date ON public.daily_usage USING btree (date);


--
-- Name: idx_daily_usage_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_usage_user_id ON public.daily_usage USING btree (user_id);


--
-- Name: idx_payments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_status ON public.payments USING btree (status);


--
-- Name: idx_payments_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_user_id ON public.payments USING btree (user_id);


--
-- Name: idx_user_week_penalties_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_week_penalties_status ON public.user_week_penalties USING btree (status);


--
-- Name: idx_user_week_penalties_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_week_penalties_user_id ON public.user_week_penalties USING btree (user_id);


--
-- Name: commitments commitments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments
    ADD CONSTRAINT commitments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: daily_usage daily_usage_commitment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usage
    ADD CONSTRAINT daily_usage_commitment_id_fkey FOREIGN KEY (commitment_id) REFERENCES public.commitments(id) ON DELETE CASCADE;


--
-- Name: daily_usage daily_usage_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usage
    ADD CONSTRAINT daily_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payments payments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payments payments_week_start_date_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_week_start_date_fkey FOREIGN KEY (week_start_date) REFERENCES public.weekly_pools(week_start_date);


--
-- Name: usage_adjustments usage_adjustments_commitment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_adjustments
    ADD CONSTRAINT usage_adjustments_commitment_id_fkey FOREIGN KEY (commitment_id) REFERENCES public.commitments(id) ON DELETE CASCADE;


--
-- Name: usage_adjustments usage_adjustments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_adjustments
    ADD CONSTRAINT usage_adjustments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_week_penalties user_week_penalties_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_week_penalties
    ADD CONSTRAINT user_week_penalties_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_week_penalties user_week_penalties_week_start_date_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_week_penalties
    ADD CONSTRAINT user_week_penalties_week_start_date_fkey FOREIGN KEY (week_start_date) REFERENCES public.weekly_pools(week_start_date);


--
-- Name: commitments Users can insert own commitments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own commitments" ON public.commitments FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: daily_usage Users can insert own daily usage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own daily usage" ON public.daily_usage FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: usage_adjustments Users can read own adjustments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read own adjustments" ON public.usage_adjustments FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: commitments Users can read own commitments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read own commitments" ON public.commitments FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: daily_usage Users can read own daily usage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read own daily usage" ON public.daily_usage FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: users Users can read own data; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read own data" ON public.users FOR SELECT USING ((auth.uid() = id));


--
-- Name: payments Users can read own payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read own payments" ON public.payments FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: user_week_penalties Users can read own penalties; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read own penalties" ON public.user_week_penalties FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: weekly_pools Users can read weekly pools; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read weekly pools" ON public.weekly_pools FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: commitments Users can update own commitments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own commitments" ON public.commitments FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: daily_usage Users can update own daily usage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own daily usage" ON public.daily_usage FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: users Users can update own data; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own data" ON public.users FOR UPDATE USING ((auth.uid() = id));


--
-- Name: commitments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.commitments ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_usage; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_usage ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: usage_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.usage_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: user_week_penalties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_week_penalties ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: weekly_pools; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weekly_pools ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION call_weekly_close(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.call_weekly_close() TO anon;
GRANT ALL ON FUNCTION public.call_weekly_close() TO authenticated;
GRANT ALL ON FUNCTION public.call_weekly_close() TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION rpc_create_commitment(p_deadline_date date, p_limit_minutes integer, p_penalty_per_minute_cents integer, p_apps_to_limit jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_create_commitment(p_deadline_date date, p_limit_minutes integer, p_penalty_per_minute_cents integer, p_apps_to_limit jsonb) TO anon;
GRANT ALL ON FUNCTION public.rpc_create_commitment(p_deadline_date date, p_limit_minutes integer, p_penalty_per_minute_cents integer, p_apps_to_limit jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_create_commitment(p_deadline_date date, p_limit_minutes integer, p_penalty_per_minute_cents integer, p_apps_to_limit jsonb) TO service_role;


--
-- Name: FUNCTION rpc_get_week_status(p_week_start_date date); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_get_week_status(p_week_start_date date) TO anon;
GRANT ALL ON FUNCTION public.rpc_get_week_status(p_week_start_date date) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_get_week_status(p_week_start_date date) TO service_role;


--
-- Name: FUNCTION rpc_report_usage(p_date date, p_week_start_date date, p_used_minutes integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_report_usage(p_date date, p_week_start_date date, p_used_minutes integer) TO anon;
GRANT ALL ON FUNCTION public.rpc_report_usage(p_date date, p_week_start_date date, p_used_minutes integer) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_report_usage(p_date date, p_week_start_date date, p_used_minutes integer) TO service_role;


--
-- Name: FUNCTION rpc_setup_test_data(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_setup_test_data() TO anon;
GRANT ALL ON FUNCTION public.rpc_setup_test_data() TO authenticated;
GRANT ALL ON FUNCTION public.rpc_setup_test_data() TO service_role;


--
-- Name: FUNCTION rpc_setup_test_data(p_real_user_email text, p_real_user_stripe_customer text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_setup_test_data(p_real_user_email text, p_real_user_stripe_customer text) TO anon;
GRANT ALL ON FUNCTION public.rpc_setup_test_data(p_real_user_email text, p_real_user_stripe_customer text) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_setup_test_data(p_real_user_email text, p_real_user_stripe_customer text) TO service_role;


--
-- Name: FUNCTION rpc_sync_daily_usage(p_entries jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rpc_sync_daily_usage(p_entries jsonb) TO anon;
GRANT ALL ON FUNCTION public.rpc_sync_daily_usage(p_entries jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.rpc_sync_daily_usage(p_entries jsonb) TO service_role;


--
-- Name: TABLE commitments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.commitments TO anon;
GRANT ALL ON TABLE public.commitments TO authenticated;
GRANT ALL ON TABLE public.commitments TO service_role;


--
-- Name: TABLE daily_usage; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.daily_usage TO anon;
GRANT ALL ON TABLE public.daily_usage TO authenticated;
GRANT ALL ON TABLE public.daily_usage TO service_role;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payments TO anon;
GRANT ALL ON TABLE public.payments TO authenticated;
GRANT ALL ON TABLE public.payments TO service_role;


--
-- Name: TABLE usage_adjustments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.usage_adjustments TO anon;
GRANT ALL ON TABLE public.usage_adjustments TO authenticated;
GRANT ALL ON TABLE public.usage_adjustments TO service_role;


--
-- Name: TABLE user_week_penalties; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.user_week_penalties TO anon;
GRANT ALL ON TABLE public.user_week_penalties TO authenticated;
GRANT ALL ON TABLE public.user_week_penalties TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.users TO anon;
GRANT ALL ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: TABLE weekly_pools; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.weekly_pools TO anon;
GRANT ALL ON TABLE public.weekly_pools TO authenticated;
GRANT ALL ON TABLE public.weekly_pools TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict 4SxJtsyILKGc4TuZqCyRX9liDc256r2UEhA74iDwoaJi7aaZBUZYEQc1rNnO4tT

