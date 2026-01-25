CREATE OR REPLACE FUNCTION public.rpc_cleanup_test_data(
  p_delete_test_users boolean DEFAULT false,
  p_real_user_email text DEFAULT 'jef+stripe@cavens.io'::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_test_user_ids uuid[] := ARRAY[
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid,
    '44444444-4444-4444-4444-444444444444'::uuid
  ];
  v_real_user_id uuid;
  v_all_test_ids uuid[];
  v_deleted_payments int := 0;
  v_deleted_daily_usage int := 0;
  v_deleted_week_penalties int := 0;
  v_deleted_commitments int := 0;
  v_deleted_pools int := 0;
  v_deleted_users int := 0;
BEGIN
  -- Look up real user ID if email provided
  IF p_real_user_email IS NOT NULL AND p_real_user_email != '' THEN
    SELECT id INTO v_real_user_id
    FROM auth.users
    WHERE email = p_real_user_email
    LIMIT 1;
    
    IF v_real_user_id IS NOT NULL THEN
      v_all_test_ids := array_append(v_test_user_ids, v_real_user_id);
    ELSE
      v_all_test_ids := v_test_user_ids;
    END IF;
  ELSE
    v_all_test_ids := v_test_user_ids;
  END IF;

  -- Delete in order to respect foreign key constraints
  
  -- 1. Delete payments for test users
  DELETE FROM public.payments
  WHERE user_id = ANY(v_all_test_ids);
  GET DIAGNOSTICS v_deleted_payments = ROW_COUNT;

  -- 2. Delete daily_usage for test users
  DELETE FROM public.daily_usage
  WHERE user_id = ANY(v_all_test_ids);
  GET DIAGNOSTICS v_deleted_daily_usage = ROW_COUNT;

  -- 3. Delete user_week_penalties for test users
  DELETE FROM public.user_week_penalties
  WHERE user_id = ANY(v_all_test_ids);
  GET DIAGNOSTICS v_deleted_week_penalties = ROW_COUNT;

  -- 4. Delete commitments for test users
  DELETE FROM public.commitments
  WHERE user_id = ANY(v_all_test_ids);
  GET DIAGNOSTICS v_deleted_commitments = ROW_COUNT;

  -- 5. Delete weekly_pools that have no remaining commitments AND no user_week_penalties
  -- (Only pools that were created for testing)
  -- FIXED: Changed from c.week_end_date = wp.week_end_date to timestamp-based lookup
  -- Also check that there are no user_week_penalties referencing this pool
  DELETE FROM public.weekly_pools wp
  WHERE NOT EXISTS (
    SELECT 1 FROM public.commitments c
    WHERE DATE(c.week_end_timestamp AT TIME ZONE 'America/New_York') = wp.week_start_date
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.user_week_penalties uwp
    WHERE uwp.week_start_date = wp.week_start_date
  );
  GET DIAGNOSTICS v_deleted_pools = ROW_COUNT;

  -- 6. Optionally delete test users themselves
  IF p_delete_test_users THEN
    DELETE FROM public.users
    WHERE id = ANY(v_test_user_ids)
      AND is_test_user = true;
    GET DIAGNOSTICS v_deleted_users = ROW_COUNT;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Test data cleanup complete',
    'deleted', json_build_object(
      'payments', v_deleted_payments,
      'daily_usage', v_deleted_daily_usage,
      'user_week_penalties', v_deleted_week_penalties,
      'commitments', v_deleted_commitments,
      'weekly_pools', v_deleted_pools,
      'users', v_deleted_users
    ),
    'test_user_ids_cleaned', v_all_test_ids
  );
END;
$function$
