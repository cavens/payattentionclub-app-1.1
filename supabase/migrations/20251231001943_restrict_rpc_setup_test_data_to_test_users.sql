-- ==============================================================================
-- Migration: Restrict rpc_setup_test_data to test users only
-- Date: 2025-12-31
-- Purpose: Prevent regular users from calling test data setup function
-- ==============================================================================
-- 
-- This function should only be callable by test users (is_test_user = true).
-- Regular users should not be able to create test data.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_setup_test_data(
  p_real_user_email text DEFAULT 'jef+stripe@cavens.io',
  p_real_user_stripe_customer text DEFAULT 'cus_TRROpBSIbBGe2M'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_test_user boolean;
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
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Check if user is a test user
  SELECT COALESCE(is_test_user, false) INTO v_is_test_user
  FROM public.users
  WHERE id = v_user_id;

  IF COALESCE(v_is_test_user, false) = false THEN
    RAISE EXCEPTION 'Only test users can call this function. Set is_test_user = true in users table.' USING ERRCODE = '42501';
  END IF;

  -- Rest of function remains the same...
  IF EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN
    v_deadline_date := CURRENT_DATE;
  ELSIF EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN
    v_deadline_date := CURRENT_DATE + 1;
  ELSE
    v_deadline_date := CURRENT_DATE - (EXTRACT(DOW FROM CURRENT_DATE)::int - 1);
  END IF;
  v_start_date := CURRENT_DATE;

  SELECT id INTO v_real_user_id
  FROM auth.users
  WHERE email = v_real_user_email
  LIMIT 1;

  IF v_real_user_id IS NULL THEN
    v_real_user_id := v_seed_real_user_id;
  END IF;

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
    v_real_user_stripe_customer,
    true,
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    stripe_customer_id = v_real_user_stripe_customer,
    has_active_payment_method = true,
    is_test_user = true;

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
      60,
      10,
      '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
      'active',
      'ok',
      4200,
      NOW()
    )
    RETURNING id INTO v_commitment_1_id;
  END IF;

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
    120,
    5,
    '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
    'active',
    'ok',
    6000,
    NOW()
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_commitment_2_id;

  IF v_commitment_2_id IS NULL THEN
    SELECT id INTO v_commitment_2_id
    FROM public.commitments
    WHERE user_id = v_test_user_1_id
      AND week_end_date = v_deadline_date
    LIMIT 1;
  END IF;

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
    180,
    3,
    '{"app_bundle_ids": ["com.apple.Safari"], "categories": []}'::jsonb,
    'active',
    'ok',
    5400,
    NOW()
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_commitment_3_id;

  IF v_commitment_3_id IS NULL THEN
    SELECT id INTO v_commitment_3_id
    FROM public.commitments
    WHERE user_id = v_test_user_3_id
      AND week_end_date = v_deadline_date
    LIMIT 1;
  END IF;

  IF v_real_user_id IS NOT NULL AND v_commitment_1_id IS NOT NULL THEN
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
      150,
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

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
      0,
      false,
      NOW()
    )
    ON CONFLICT (user_id, date, commitment_id) DO UPDATE SET
      used_minutes = EXCLUDED.used_minutes,
      exceeded_minutes = EXCLUDED.exceeded_minutes,
      penalty_cents = EXCLUDED.penalty_cents;
  END IF;

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

-- Update comment to reflect security restriction
COMMENT ON FUNCTION public.rpc_setup_test_data(text, text) IS 
'Setup test data for testing purposes. 
WARNING: Only callable by test users (is_test_user = true).
This function creates test users, commitments, and usage data.
Should only be used in test/staging environments.';

