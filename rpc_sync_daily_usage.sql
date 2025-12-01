-- RPC Function: rpc_sync_daily_usage
-- Purpose: Batch sync multiple daily usage entries in one call
-- Phase 5: Backend Changes - Batch Sync Support
-- 
-- Input: JSON array of daily usage entries
-- Output: JSON object with sync results

CREATE OR REPLACE FUNCTION public."rpc_sync_daily_usage"("p_entries" jsonb) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_entry jsonb;
  v_date date;
  v_week_start_date date;
  v_used_minutes integer;
  v_commitment_id uuid;
  v_limit_minutes integer;
  v_penalty_per_minute_cents integer;
  v_exceeded_minutes integer;
  v_penalty_cents integer;
  v_synced_dates text[] := ARRAY[]::text[];
  v_failed_dates text[] := ARRAY[]::text[];
  v_errors text[] := ARRAY[]::text[];
  v_user_week_total_cents integer;
  v_pool_total_cents integer;
  v_result json;
  v_processed_weeks date[] := ARRAY[]::date[];
  v_week date;
BEGIN
  -- 1) Must be authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- 2) Validate input is an array
  IF jsonb_typeof(p_entries) != 'array' THEN
    RAISE EXCEPTION 'p_entries must be a JSON array' USING ERRCODE = '22023';
  END IF;

  -- 3) Process each entry
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    BEGIN
      -- Extract entry fields
      v_date := (v_entry->>'date')::date;
      v_week_start_date := (v_entry->>'week_start_date')::date;
      v_used_minutes := (v_entry->>'used_minutes')::integer;

      -- Validate required fields
      IF v_date IS NULL OR v_week_start_date IS NULL OR v_used_minutes IS NULL THEN
        v_failed_dates := array_append(v_failed_dates, COALESCE(v_entry->>'date', 'unknown'));
        v_errors := array_append(v_errors, format('Invalid entry: missing required fields'));
        CONTINUE;
      END IF;

      -- Find the active commitment for this user and week
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
        AND c.week_end_date = v_week_start_date  -- Match by deadline (week_end_date)
        AND c.status IN ('pending', 'active')
      ORDER BY c.created_at DESC
      LIMIT 1;

      -- Check if commitment exists
      IF v_commitment_id IS NULL THEN
        v_failed_dates := array_append(v_failed_dates, v_date::text);
        v_errors := array_append(v_errors, format('No active commitment found for week %s', v_week_start_date::text));
        CONTINUE;
      END IF;

      -- Calculate exceeded minutes and penalty
      v_exceeded_minutes := GREATEST(0, v_used_minutes - v_limit_minutes);
      v_penalty_cents := v_exceeded_minutes * v_penalty_per_minute_cents;

      -- Upsert into daily_usage
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
        v_date,
        v_used_minutes,
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

      -- Track this week for recalculation (avoid duplicates)
      IF NOT (v_week_start_date = ANY(v_processed_weeks)) THEN
        v_processed_weeks := array_append(v_processed_weeks, v_week_start_date);
      END IF;

      -- Mark as successfully synced
      v_synced_dates := array_append(v_synced_dates, v_date::text);

    EXCEPTION
      WHEN OTHERS THEN
        -- Log error and continue with next entry
        v_failed_dates := array_append(v_failed_dates, COALESCE(v_date::text, 'unknown'));
        v_errors := array_append(v_errors, format('Error processing %s: %s', COALESCE(v_date::text, 'unknown'), SQLERRM));
    END;
  END LOOP;

  -- 4) Recalculate weekly totals for each unique week that was processed
  FOREACH v_week IN ARRAY v_processed_weeks
  LOOP
    BEGIN
      -- Recalculate user_week_penalties for this week
      SELECT COALESCE(SUM(penalty_cents), 0)
      INTO v_user_week_total_cents
      FROM public.daily_usage du
      JOIN public.commitments c ON du.commitment_id = c.id
      WHERE du.user_id = v_user_id
        AND c.week_end_date = v_week  -- Match by deadline
        AND du.date >= c.week_start_date
        AND du.date <= c.week_end_date;

      -- Upsert user_week_penalties
      INSERT INTO public.user_week_penalties (
        user_id,
        week_start_date,  -- Actually stores the deadline
        total_penalty_cents,
        status,
        last_updated
      )
      VALUES (
        v_user_id,
        v_week,  -- Deadline (next Monday)
        v_user_week_total_cents,
        'pending',
        NOW()
      )
      ON CONFLICT (user_id, week_start_date)
      DO UPDATE SET
        total_penalty_cents = EXCLUDED.total_penalty_cents,
        last_updated = NOW();

      -- Recalculate weekly_pools for this week
      SELECT COALESCE(SUM(total_penalty_cents), 0)
      INTO v_pool_total_cents
      FROM public.user_week_penalties
      WHERE week_start_date = v_week;

      -- Upsert weekly_pools
      INSERT INTO public.weekly_pools (
        week_start_date,  -- Deadline (next Monday) - used as pool identifier
        week_end_date,    -- Same as start (deadline is the pool identifier)
        total_penalty_cents,
        status
      )
      VALUES (
        v_week,  -- Deadline (next Monday)
        v_week,  -- Same as start (deadline is the pool identifier)
        v_pool_total_cents,
        'open'
      )
      ON CONFLICT (week_start_date)
      DO UPDATE SET
        total_penalty_cents = EXCLUDED.total_penalty_cents;

    EXCEPTION
      WHEN OTHERS THEN
        -- Log error but don't fail the entire sync
        v_errors := array_append(v_errors, format('Error recalculating totals for week %s: %s', v_week::text, SQLERRM));
    END;
  END LOOP;

  -- 5) Return result as JSON
  SELECT json_build_object(
    'synced_count', array_length(v_synced_dates, 1),
    'failed_count', array_length(v_failed_dates, 1),
    'synced_dates', v_synced_dates,
    'failed_dates', v_failed_dates,
    'errors', v_errors,
    'processed_weeks', v_processed_weeks
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

-- Grant execute permission to authenticated users
ALTER FUNCTION public."rpc_sync_daily_usage"("p_entries" jsonb) OWNER TO "postgres";
GRANT EXECUTE ON FUNCTION public."rpc_sync_daily_usage"("p_entries" jsonb) TO authenticated;


