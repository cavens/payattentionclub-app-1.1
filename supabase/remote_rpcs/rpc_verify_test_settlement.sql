-- ==============================================================================
-- Function: Verify Test Settlement Results
-- Purpose: Get complete verification for a user's test commitment (read-only)
-- Called by: testing-command-runner Edge Function (verify_results command)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_verify_test_settlement(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_result json;
  v_commitment json;
  v_penalty json;
  v_payments json;
  v_usage_count integer;
  v_penalty_record RECORD;
BEGIN
  -- Check if penalty needs reconciliation (read-only check)
  SELECT * INTO v_penalty_record
  FROM public.user_week_penalties
  WHERE user_id = p_user_id
  ORDER BY week_start_date DESC
  LIMIT 1;

  -- Get latest commitment
  SELECT row_to_json(c.*) INTO v_commitment
  FROM public.commitments c
  WHERE c.user_id = p_user_id
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- Get latest penalty record
  IF v_penalty_record.id IS NOT NULL THEN
    SELECT row_to_json(uwp.*) INTO v_penalty
    FROM public.user_week_penalties uwp
    WHERE uwp.id = v_penalty_record.id;
  ELSE
    SELECT row_to_json(uwp.*) INTO v_penalty
    FROM public.user_week_penalties uwp
    WHERE uwp.user_id = p_user_id
    ORDER BY uwp.week_start_date DESC
    LIMIT 1;
  END IF;

  -- Get all payments
  SELECT json_agg(row_to_json(p.*)) INTO v_payments
  FROM (
    SELECT *
    FROM public.payments
    WHERE user_id = p_user_id
    ORDER BY created_at DESC
  ) p;

  -- Count usage entries
  SELECT COUNT(*) INTO v_usage_count
  FROM public.daily_usage
  WHERE user_id = p_user_id;

  -- Build result
  v_result := json_build_object(
    'commitment', v_commitment,
    'penalty', v_penalty,
    'payments', COALESCE(v_payments, '[]'::json),
    'usage_count', v_usage_count,
    'verification_time', NOW()
  );

  RETURN v_result;
END;
$$;

