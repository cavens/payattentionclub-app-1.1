-- RPC function to set up test data for weekly-close testing
-- Creates test users, commitments, daily_usage, and weekly_pools

CREATE OR REPLACE FUNCTION public.rpc_setup_test_data()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
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

