-- ==============================================================================
-- Migration: Add rpc_verify_test_settlement Function
-- ==============================================================================
-- Date: 2026-01-07
-- Purpose: Add verification function for settlement testing
-- 
-- This function returns all test-related data for a user in a single JSON object.
-- Used to verify settlement test results after running tests.
-- Part of Phase 3: Verification Tools
-- ==============================================================================

/**
 * Verification Function for Test Settlement Results
 * 
 * Returns all test-related data for a user in a single JSON object.
 * Used to verify settlement test results after running tests.
 * 
 * Usage:
 *   SELECT rpc_verify_test_settlement('user-id-here');
 */

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
BEGIN
  -- Get latest commitment
  SELECT row_to_json(c.*) INTO v_commitment
  FROM public.commitments c
  WHERE c.user_id = p_user_id
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- Get latest penalty record
  SELECT row_to_json(uwp.*) INTO v_penalty
  FROM public.user_week_penalties uwp
  WHERE uwp.user_id = p_user_id
  ORDER BY uwp.week_start_date DESC
  LIMIT 1;

  -- Get all payments
  SELECT json_agg(row_to_json(p.*) ORDER BY p.created_at DESC) INTO v_payments
  FROM public.payments p
  WHERE p.user_id = p_user_id;

  -- Count usage entries
  SELECT COUNT(*) INTO v_usage_count
  FROM public.daily_usage
  WHERE user_id = p_user_id;

  -- Build result
  v_result := json_build_object(
    'commitment', COALESCE(v_commitment, 'null'::json),
    'penalty', COALESCE(v_penalty, 'null'::json),
    'payments', COALESCE(v_payments, '[]'::json),
    'usage_count', COALESCE(v_usage_count, 0),
    'verification_time', NOW()
  );

  RETURN v_result;
END;
$$;

-- Add comment
COMMENT ON FUNCTION public.rpc_verify_test_settlement(uuid) IS 
'Returns all test-related data for a user in a single JSON object.
Used to verify settlement test results after running tests.
Returns: commitment, penalty, payments, usage_count, and verification_time.';

