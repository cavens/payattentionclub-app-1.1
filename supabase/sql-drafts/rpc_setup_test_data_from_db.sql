CREATE OR REPLACE FUNCTION public."rpc_setup_test_data"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
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
  -- Calculate deadline (next Monday)
  v_deadline_date := CURRENT_DATE + (8 - EXTRACT(DOW FROM CURRENT_DATE)::int) % 7;
  IF EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN
    -- If today is Monday, use next Monday
    v_deadline_date := CURRENT_DATE + 7;
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
      created_at,
      updated_at
    )
    VALUES (
      v_real_user_id,
      'jef+stripe@cavens.io',
      'cus_TRROpBSIbBGe2M',
      true,
      true,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      stripe_customer_id = 'cus_TRROpBSIbBGe2M',
      has_active_payment_method = true,
      is_test_user = true,
      updated_at = NOW();
  END IF;

  -- 2) Create/update test users (these won't have auth.users entries, but we'll create public.users entries)
  -- Test User 1: Has penalties, will be charged
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at,
    updated_at
  )
  VALUES (
    v_test_user_1_id,
    'test-user-1@example.com',
    'cus_test_user_1',
    true,
    true,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user,
    updated_at = NOW();

  -- Test User 2: Has penalties, will be charged
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at,
    updated_at
  )
  VALUES (
    v_test_user_2_id,
    'test-user-2@example.com',
    'cus_test_user_2',
    true,
    true,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user,
    updated_at = NOW();

  -- Test User 3: No penalties (stayed within limit)
  INSERT INTO public.users (
    id,
    email,
    stripe_customer_id,
    has_active_payment_method,
    is_test_user,
    created_at,
    updated_at
  )
  VALUES (
    v_test_user_3_id,
    'test-user-3@example.com',
    'cus_test_user_3',
    true,
    true,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = EXCLUDED.stripe_customer_id,
    has_active_payment_method = EXCLUDED.has_active_payment_method,
    is_test_user = EXCLUDED.is_test_user,
    updated_at = NOW();

  -- 3) Create weekly pool for this week
  INSERT INTO public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status,
    created_at
  )
  VALUES (
    v_deadline_date,
    v_deadline_date,
    0,
    'open',
    NOW()
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
