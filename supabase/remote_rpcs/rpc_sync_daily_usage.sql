CREATE OR REPLACE FUNCTION public.rpc_sync_daily_usage(
  p_entries jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
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
  v_prev_settlement_status text;
  v_prev_charged_amount integer;
  v_prev_payment_intent_id text;
  v_prev_needs_reconciliation boolean;
  v_needs_reconciliation boolean;
  v_reconciliation_delta integer;
  v_max_charge_cents integer;
  v_capped_actual_cents integer;
  v_week_deadline_timestamp timestamptz;
  v_week_grace_expires_at timestamptz;
  v_week_start_ts_start timestamptz;  -- For timestamp range lookup
  v_week_start_ts_end timestamptz;    -- For timestamp range lookup
  v_week_ts_start timestamptz;        -- For timestamp range lookup in second loop
  v_week_ts_end timestamptz;          -- For timestamp range lookup in second loop
  V_SETTLED_STATUSES CONSTANT text[] := ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial'];
  V_STRIPE_MINIMUM_CENTS CONSTANT integer := 60; -- Stripe minimum charge (matches bright-service)
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF jsonb_typeof(p_entries) != 'array' THEN
    RAISE EXCEPTION 'p_entries must be a JSON array' USING ERRCODE = '22023';
  END IF;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    BEGIN
      v_date := (v_entry->>'date')::date;
      v_week_start_date := (v_entry->>'week_start_date')::date;
      v_used_minutes := (v_entry->>'used_minutes')::integer;

      IF v_date IS NULL OR v_week_start_date IS NULL OR v_used_minutes IS NULL THEN
        v_failed_dates := array_append(v_failed_dates, COALESCE(v_entry->>'date', 'unknown'));
        v_errors := array_append(v_errors, format('Invalid entry: missing required fields'));
        CONTINUE;
      END IF;

      -- Lookup commitment using timestamp range (same day in ET timezone)
      -- Convert v_week_start_date (date) to timestamp range
      v_week_start_ts_start := (v_week_start_date::timestamp AT TIME ZONE 'America/New_York') AT TIME ZONE 'UTC';
      v_week_start_ts_end := v_week_start_ts_start + INTERVAL '1 day';
      
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
        AND c.week_end_timestamp >= v_week_start_ts_start
        AND c.week_end_timestamp < v_week_start_ts_end
        AND c.status IN ('pending', 'active')
      ORDER BY c.created_at DESC
      LIMIT 1;

      IF v_commitment_id IS NULL THEN
        v_failed_dates := array_append(v_failed_dates, v_date::text);
        v_errors := array_append(v_errors, format('No active commitment found for week %s', v_week_start_date::text));
        CONTINUE;
      END IF;

      v_exceeded_minutes := GREATEST(0, v_used_minutes - v_limit_minutes);
      v_penalty_cents := v_exceeded_minutes * v_penalty_per_minute_cents;

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

      IF NOT (v_week_start_date = ANY(v_processed_weeks)) THEN
        v_processed_weeks := array_append(v_processed_weeks, v_week_start_date);
      END IF;

      v_synced_dates := array_append(v_synced_dates, v_date::text);

    EXCEPTION
      WHEN OTHERS THEN
        v_failed_dates := array_append(v_failed_dates, COALESCE(v_date::text, 'unknown'));
        v_errors := array_append(v_errors, format('Error processing %s: %s', COALESCE(v_date::text, 'unknown'), SQLERRM));
    END;
  END LOOP;

  FOREACH v_week IN ARRAY v_processed_weeks
  LOOP
    BEGIN
      -- Convert v_week (date) to timestamp range for lookup
      v_week_ts_start := (v_week::timestamp AT TIME ZONE 'America/New_York') AT TIME ZONE 'UTC';
      v_week_ts_end := v_week_ts_start + INTERVAL '1 day';
      
      SELECT COALESCE(SUM(penalty_cents), 0)
      INTO v_user_week_total_cents
      FROM public.daily_usage du
      JOIN public.commitments c ON du.commitment_id = c.id
      WHERE du.user_id = v_user_id
        AND c.week_end_timestamp >= v_week_ts_start
        AND c.week_end_timestamp < v_week_ts_end
        AND du.date >= c.week_start_date
        AND du.date <= DATE(c.week_end_timestamp AT TIME ZONE 'America/New_York');

      v_prev_settlement_status := NULL;
      v_prev_charged_amount := 0;
      v_prev_payment_intent_id := NULL;
      v_prev_needs_reconciliation := false;
      BEGIN
        SELECT 
          settlement_status, 
          COALESCE(charged_amount_cents, 0), 
          charge_payment_intent_id,
          COALESCE(needs_reconciliation, false)
        INTO 
          v_prev_settlement_status, 
          v_prev_charged_amount, 
          v_prev_payment_intent_id,
          v_prev_needs_reconciliation
        FROM public.user_week_penalties
        WHERE user_id = v_user_id
          AND week_start_date = v_week;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_prev_settlement_status := NULL;
          v_prev_charged_amount := 0;
          v_prev_payment_intent_id := NULL;
          v_prev_needs_reconciliation := false;
      END;

      -- Get max_charge_cents (authorization amount) and timing info from the commitment
      -- Use timestamp range lookup (v_week_ts_start and v_week_ts_end already calculated above)
      SELECT 
        max_charge_cents,
        week_end_timestamp,
        week_grace_expires_at
      INTO 
        v_max_charge_cents,
        v_week_deadline_timestamp,
        v_week_grace_expires_at
      FROM public.commitments
      WHERE user_id = v_user_id
        AND week_end_timestamp >= v_week_ts_start
        AND week_end_timestamp < v_week_ts_end
      LIMIT 1;

      -- Cap actual penalty at authorization amount (same logic as settlement)
      v_capped_actual_cents := LEAST(
        v_user_week_total_cents,
        COALESCE(v_max_charge_cents, v_user_week_total_cents)
      );

      v_needs_reconciliation := false;
      v_reconciliation_delta := 0;
      IF v_prev_settlement_status = ANY(V_SETTLED_STATUSES) THEN
        -- Special case: If previous charge was 0 due to below-minimum, and current actual is also below minimum,
        -- skip reconciliation (we can't charge the actual amount anyway, so no change is needed)
        IF v_prev_charged_amount = 0 
           AND v_prev_payment_intent_id IN ('below_minimum', 'zero_amount')
           AND v_capped_actual_cents < V_STRIPE_MINIMUM_CENTS THEN
          -- Both previous charge and current actual are below minimum - no reconciliation needed
          v_reconciliation_delta := 0;
          v_needs_reconciliation := false;
        ELSE
          -- Use capped actual for reconciliation delta (not raw actual)
          v_reconciliation_delta := v_capped_actual_cents - COALESCE(v_prev_charged_amount, 0);
          IF v_reconciliation_delta <> 0 THEN
            v_needs_reconciliation := true;
          END IF;
        END IF;
      END IF;

      INSERT INTO public.user_week_penalties (
        user_id,
        week_start_date,
        total_penalty_cents,
        status,
        settlement_status,
        actual_amount_cents,
        needs_reconciliation,
        reconciliation_delta_cents,
        reconciliation_reason,
        reconciliation_detected_at,
        last_updated
      )
      VALUES (
        v_user_id,
        v_week,
        v_user_week_total_cents,
        'pending',
        COALESCE(v_prev_settlement_status, 'pending'),
        v_capped_actual_cents,  -- Use capped value to match settlement logic
        v_needs_reconciliation,
        CASE WHEN v_needs_reconciliation THEN v_reconciliation_delta ELSE 0 END,
        CASE WHEN v_needs_reconciliation THEN 'late_sync_delta' ELSE NULL END,
        CASE WHEN v_needs_reconciliation THEN NOW() ELSE NULL END,
        NOW()
      )
      ON CONFLICT (user_id, week_start_date)
      DO UPDATE SET
        total_penalty_cents = EXCLUDED.total_penalty_cents,
        -- CRITICAL: Always update actual_amount_cents when usage is synced, even if already settled
        -- This ensures settlement can see the actual usage for reconciliation
        -- Use capped value to match settlement logic (capped at max_charge_cents)
        actual_amount_cents = EXCLUDED.actual_amount_cents,
        needs_reconciliation = EXCLUDED.needs_reconciliation,
        reconciliation_delta_cents = EXCLUDED.reconciliation_delta_cents,
        reconciliation_reason = CASE
          WHEN EXCLUDED.needs_reconciliation THEN EXCLUDED.reconciliation_reason
          ELSE NULL
        END,
        reconciliation_detected_at = CASE
          WHEN EXCLUDED.needs_reconciliation AND public.user_week_penalties.needs_reconciliation = false
            THEN EXCLUDED.reconciliation_detected_at
          WHEN EXCLUDED.needs_reconciliation
            THEN COALESCE(public.user_week_penalties.reconciliation_detected_at, EXCLUDED.reconciliation_detected_at)
          ELSE NULL
        END,
        -- Preserve existing settlement_status if already settled, but allow updates if pending
        settlement_status = CASE
          WHEN public.user_week_penalties.settlement_status = ANY(V_SETTLED_STATUSES) 
            THEN public.user_week_penalties.settlement_status  -- Keep existing settled status
          ELSE COALESCE(public.user_week_penalties.settlement_status, EXCLUDED.settlement_status)  -- Allow update if pending
        END,
        -- Update last_updated if:
        -- 1. It doesn't exist yet (first sync), OR
        -- 2. Current sync is within grace period (capture grace period syncs)
        -- This ensures we track the FIRST sync within grace, not just the first sync ever
        last_updated = CASE
          WHEN public.user_week_penalties.last_updated IS NULL THEN NOW()  -- First sync
          WHEN v_week_deadline_timestamp IS NOT NULL 
               AND v_week_grace_expires_at IS NOT NULL
               AND NOW() > v_week_deadline_timestamp 
               AND NOW() <= v_week_grace_expires_at
            THEN NOW()  -- Current sync is within grace period - update it
          ELSE public.user_week_penalties.last_updated  -- Preserve existing (sync was after grace or before deadline)
        END;

      -- The queue will be processed by a cron job that can use pg_net (which works in cron context)
      IF v_needs_reconciliation AND NOT v_prev_needs_reconciliation THEN
        BEGIN
          -- Log that we're queuing reconciliation
          RAISE NOTICE 'Queuing automatic reconciliation for user % week % (delta: % cents)', 
            v_user_id, v_week, v_reconciliation_delta;

          -- Insert into reconciliation queue (will be processed by cron job)
          -- Use ON CONFLICT to handle race conditions (multiple syncs at once)
          -- The partial unique index ensures only one pending entry per user/week
          INSERT INTO public.reconciliation_queue (
            user_id,
            week_start_date,
            reconciliation_delta_cents,
            status,
            created_at
          )
          VALUES (
            v_user_id,
            v_week,
            v_reconciliation_delta,
            'pending',
            NOW()
          )
          ON CONFLICT (user_id, week_start_date) 
          WHERE status = 'pending'
          DO UPDATE SET
            reconciliation_delta_cents = EXCLUDED.reconciliation_delta_cents,
            created_at = EXCLUDED.created_at,
            retry_count = 0; -- Reset retry count if re-queued
          
          RAISE NOTICE '✅ Reconciliation queued successfully for user % week %', 
            v_user_id, v_week;
        EXCEPTION
          WHEN OTHERS THEN
            -- Don't fail the sync if queue insert fails
            -- The reconciliation can be triggered manually later if needed
            RAISE WARNING '❌ Failed to queue reconciliation for user % week %: %', 
              v_user_id, v_week, SQLERRM;
        END;
      ELSE
        -- Log why reconciliation wasn't triggered (for debugging)
        IF v_needs_reconciliation THEN
          RAISE NOTICE 'Reconciliation needed but not triggered: prev_needs_reconciliation=% (already flagged)', v_prev_needs_reconciliation;
        END IF;
      END IF;

      SELECT COALESCE(SUM(total_penalty_cents), 0)
      INTO v_pool_total_cents
      FROM public.user_week_penalties
      WHERE week_start_date = v_week;

      INSERT INTO public.weekly_pools (
        week_start_date,
        total_penalty_cents,
        status
      )
      VALUES (
        v_week,
        v_pool_total_cents,
        'open'
      )
      ON CONFLICT (week_start_date)
      DO UPDATE SET
        total_penalty_cents = EXCLUDED.total_penalty_cents;

    EXCEPTION
      WHEN OTHERS THEN
        v_errors := array_append(v_errors, format('Error recalculating totals for week %s: %s', v_week::text, SQLERRM));
    END;
  END LOOP;

  SELECT json_build_object(
    'synced_count', array_length(v_synced_dates, 1),
    'failed_count', array_length(v_failed_dates, 1),
    'synced_dates', v_synced_dates,
    'failed_dates', v_failed_dates,
    'errors', v_errors,
    'processed_weeks', COALESCE((
      SELECT json_agg(json_build_object(
        'week_end_date', uw.week_start_date,  -- Note: This is the date string for response, not database column
        'total_penalty_cents', uw.total_penalty_cents,
        'needs_reconciliation', uw.needs_reconciliation,
        'reconciliation_delta_cents', uw.reconciliation_delta_cents
      ))
      FROM public.user_week_penalties uw
      WHERE uw.user_id = v_user_id
        AND (v_processed_weeks IS NOT NULL AND array_length(v_processed_weeks, 1) > 0)
        AND uw.week_start_date = ANY(v_processed_weeks)
    ), '[]'::json)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;


