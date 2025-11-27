-- Migration: Add rpc_update_monitoring_status function
-- Date: 2025-11-18
-- Purpose: Add missing RPC function for updating monitoring status

-- RPC Function: rpc_update_monitoring_status
-- Purpose: Update Screen Time monitoring state for a commitment
-- Called when: iOS app detects Screen Time monitoring has been revoked or restored

CREATE OR REPLACE FUNCTION public.rpc_update_monitoring_status(
  p_commitment_id uuid,
  p_monitoring_status text  -- 'ok' or 'revoked'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_commitment public.commitments;
  v_result json;
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Fetch commitment and verify ownership
  SELECT c.*
  INTO v_commitment
  FROM public.commitments c
  WHERE c.id = p_commitment_id
    AND c.user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Commitment not found or access denied' USING ERRCODE = 'P0001';
  END IF;

  -- 3) Validate status
  IF p_monitoring_status NOT IN ('ok', 'revoked') THEN
    RAISE EXCEPTION 'Invalid monitoring_status. Must be "ok" or "revoked"' USING ERRCODE = 'P0002';
  END IF;

  -- 4) Update commitment
  -- If status is 'revoked' and monitoring_revoked_at is NULL, set it to NOW()
  -- If status is 'ok', set monitoring_revoked_at to NULL
  UPDATE public.commitments
  SET
    monitoring_status = p_monitoring_status,
    monitoring_revoked_at = CASE
      WHEN p_monitoring_status = 'revoked' THEN 
        COALESCE(monitoring_revoked_at, NOW())  -- Only set if not already set
      ELSE 
        NULL  -- Clear if status is 'ok'
    END,
    updated_at = NOW()
  WHERE id = p_commitment_id
    AND user_id = v_user_id;

  -- 5) Fetch and return updated commitment as JSON
  SELECT row_to_json(c.*)
  INTO v_result
  FROM public.commitments c
  WHERE c.id = p_commitment_id;

  RETURN v_result;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.rpc_update_monitoring_status(uuid, text) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.rpc_update_monitoring_status(uuid, text) IS 
  'Updates the monitoring status of a commitment. Called when Screen Time monitoring is revoked or restored.';



