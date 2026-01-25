CREATE OR REPLACE FUNCTION public.rpc_report_usage(
  p_date date,
  p_week_start_date date,
  p_used_minutes integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
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
    AND DATE(c.week_end_timestamp AT TIME ZONE 'America/New_York') = p_week_start_date
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
  SELECT COALESCE(SUM(penalty_cents), 0)
  INTO v_user_week_total_cents
  FROM public.daily_usage
  WHERE user_id = v_user_id
    AND commitment_id = v_commitment_id
    AND date >= (
      SELECT week_start_date
      FROM public.commitments 
      WHERE id = v_commitment_id
    )
    AND date <= (
      SELECT DATE(week_end_timestamp AT TIME ZONE 'America/New_York')
      FROM public.commitments 
      WHERE id = v_commitment_id
    );

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
    v_user_week_total_cents,
    'pending',
    NOW()
  )
  ON CONFLICT (user_id, week_start_date)
  DO UPDATE SET
    total_penalty_cents = EXCLUDED.total_penalty_cents,
    last_updated = NOW();

  -- 7) Recalculate weekly_pools
  SELECT COALESCE(SUM(total_penalty_cents), 0)
  INTO v_pool_total_cents
  FROM public.user_week_penalties
  WHERE week_start_date = p_week_start_date;

  INSERT INTO public.weekly_pools (
    week_start_date,
    total_penalty_cents,
    status
  )
  VALUES (
    p_week_start_date,
    v_pool_total_cents,
    'open'
  )
  ON CONFLICT (week_start_date)
  DO UPDATE SET
    total_penalty_cents = EXCLUDED.total_penalty_cents;

  -- 8) Return result as JSON
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


