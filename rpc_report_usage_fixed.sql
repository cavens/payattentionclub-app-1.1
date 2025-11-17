-- Fixed version of rpc_report_usage
-- Issues fixed:
-- 1. Changed to look for week_end_date (deadline) instead of week_start_date
-- 2. Changed return type to JSON to match Swift code expectations
-- 3. Fixed weekly_pools to use INSERT ... ON CONFLICT instead of UPDATE only

CREATE OR REPLACE FUNCTION public.rpc_report_usage(
  p_date date,
  p_week_start_date date,  -- Actually the deadline (next Monday before noon)
  p_used_minutes integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_commitment public.commitments;
  v_limit_minutes integer;
  v_exceeded_minutes integer;
  v_penalty_cents integer;
  v_week_penalty_total integer;
  v_pool_total integer;
  v_result json;
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Find the user's commitment for this week
  -- NOTE: week_end_date in commitments table is actually the deadline (next Monday)
  -- So we match where week_end_date equals p_week_start_date (which is the deadline)
  SELECT c.*
  INTO v_commitment
  FROM public.commitments c
  WHERE c.user_id = v_user_id
    AND c.week_end_date = p_week_start_date  -- FIXED: Use week_end_date (deadline), not week_start_date
    AND c.status IN ('pending', 'active')
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No commitment found for this user and week (%).', p_week_start_date
      USING ERRCODE = 'P0001';
  END IF;

  v_limit_minutes := v_commitment.limit_minutes;

  -- 3) Compute exceeded + penalty
  v_exceeded_minutes := GREATEST(0, p_used_minutes - v_limit_minutes);
  v_penalty_cents := v_exceeded_minutes * v_commitment.penalty_per_minute_cents;

  -- 4) Upsert into daily_usage
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
    v_user_id,
    v_commitment.id,
    p_date,
    p_used_minutes,
    v_limit_minutes,
    v_exceeded_minutes,
    v_penalty_cents,
    false,
    NOW()
  )
  ON CONFLICT (user_id, date, commitment_id)
  DO UPDATE SET
    used_minutes     = EXCLUDED.used_minutes,
    limit_minutes    = EXCLUDED.limit_minutes,
    exceeded_minutes = EXCLUDED.exceeded_minutes,
    penalty_cents    = EXCLUDED.penalty_cents,
    is_estimated     = EXCLUDED.is_estimated,
    reported_at      = EXCLUDED.reported_at;

  -- 5) Recompute user_week_penalties for this user & week
  SELECT COALESCE(SUM(du.penalty_cents), 0)
  INTO v_week_penalty_total
  FROM public.daily_usage du
  JOIN public.commitments c ON c.id = du.commitment_id
  WHERE du.user_id = v_user_id
    AND c.week_end_date = p_week_start_date;  -- FIXED: Use week_end_date (deadline)

  INSERT INTO public.user_week_penalties (
    user_id,
    week_start_date,
    total_penalty_cents,
    status,
    last_updated
  )
  VALUES (
    v_user_id,
    p_week_start_date,
    v_week_penalty_total,
    'pending',
    NOW()
  )
  ON CONFLICT (user_id, week_start_date)
  DO UPDATE SET
    total_penalty_cents = EXCLUDED.total_penalty_cents,
    last_updated        = EXCLUDED.last_updated;

  -- 6) Recompute weekly_pools.total_penalty_cents for this week
  SELECT COALESCE(SUM(uwp.total_penalty_cents), 0)
  INTO v_pool_total
  FROM public.user_week_penalties uwp
  WHERE uwp.week_start_date = p_week_start_date;

  -- FIXED: Use INSERT ... ON CONFLICT instead of UPDATE only
  INSERT INTO public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  VALUES (
    p_week_start_date,  -- Deadline (next Monday) - used as pool identifier
    p_week_start_date,  -- Same as start (deadline is the pool identifier)
    v_pool_total,
    'open'
  )
  ON CONFLICT (week_start_date)
  DO UPDATE SET
    total_penalty_cents = EXCLUDED.total_penalty_cents;

  -- 7) Return as JSON (matches Swift code expectations)
  SELECT json_build_object(
    'date', p_date::text,
    'limit_minutes', v_limit_minutes,
    'used_minutes', p_used_minutes,
    'exceeded_minutes', v_exceeded_minutes,
    'penalty_cents', v_penalty_cents,
    'user_week_total_cents', v_week_penalty_total,
    'pool_total_cents', v_pool_total
  )
  INTO v_result;

  RETURN v_result;
END;
$$;



