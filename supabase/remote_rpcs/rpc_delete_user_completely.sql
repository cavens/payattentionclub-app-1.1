-- ============================================
-- rpc_delete_user_completely
-- ============================================
-- Completely removes a user and ALL their data.
-- Use with caution! This is for development/testing only.
-- 
-- Usage: SELECT rpc_delete_user_completely('your-email@example.com');
-- ============================================

CREATE OR REPLACE FUNCTION public.rpc_delete_user_completely(
  p_email text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid;
  v_deleted_payments int := 0;
  v_deleted_daily_usage int := 0;
  v_deleted_week_penalties int := 0;
  v_deleted_commitments int := 0;
  v_deleted_public_user int := 0;
  v_deleted_auth_user int := 0;
BEGIN
  -- Validate input
  IF p_email IS NULL OR p_email = '' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Email is required'
    );
  END IF;

  -- Look up user ID from auth.users
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'User not found with email: ' || p_email
    );
  END IF;

  -- Delete in order to respect foreign key constraints
  
  -- 1. Delete payments
  DELETE FROM public.payments WHERE user_id = v_user_id;
  GET DIAGNOSTICS v_deleted_payments = ROW_COUNT;

  -- 2. Delete daily_usage
  DELETE FROM public.daily_usage WHERE user_id = v_user_id;
  GET DIAGNOSTICS v_deleted_daily_usage = ROW_COUNT;

  -- 3. Delete user_week_penalties
  DELETE FROM public.user_week_penalties WHERE user_id = v_user_id;
  GET DIAGNOSTICS v_deleted_week_penalties = ROW_COUNT;

  -- 4. Delete commitments
  DELETE FROM public.commitments WHERE user_id = v_user_id;
  GET DIAGNOSTICS v_deleted_commitments = ROW_COUNT;

  -- 5. Delete from public.users
  DELETE FROM public.users WHERE id = v_user_id;
  GET DIAGNOSTICS v_deleted_public_user = ROW_COUNT;

  -- 6. Delete from auth.users (this is the key step for fresh Apple Sign-In)
  DELETE FROM auth.users WHERE id = v_user_id;
  GET DIAGNOSTICS v_deleted_auth_user = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'message', 'User completely deleted',
    'email', p_email,
    'user_id', v_user_id,
    'deleted', json_build_object(
      'payments', v_deleted_payments,
      'daily_usage', v_deleted_daily_usage,
      'user_week_penalties', v_deleted_week_penalties,
      'commitments', v_deleted_commitments,
      'public_users', v_deleted_public_user,
      'auth_users', v_deleted_auth_user
    )
  );
END;
$$;



