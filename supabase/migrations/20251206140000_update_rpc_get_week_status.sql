-- Adds settlement metadata outputs to rpc_get_week_status so the app can display
-- grace deadlines, charged amounts, and reconciliation states.
CREATE OR REPLACE FUNCTION public."rpc_get_week_status"("p_week_start_date" date DEFAULT NULL::date) RETURNS TABLE(
    "user_total_penalty_cents" integer,
    "user_status" text,
    "user_max_charge_cents" integer,
    "pool_total_penalty_cents" integer,
    "pool_status" text,
    "pool_instagram_post_url" text,
    "pool_instagram_image_url" text,
    "user_settlement_status" text,
    "charged_amount_cents" integer,
    "actual_amount_cents" integer,
    "refund_amount_cents" integer,
    "needs_reconciliation" boolean,
    "reconciliation_delta_cents" integer,
    "reconciliation_reason" text,
    "reconciliation_detected_at" timestamp with time zone,
    "week_grace_expires_at" timestamp with time zone,
    "week_end_date" date
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_week_start_date date;
  v_commitment public.commitments;
  v_user_week_pen public.user_week_penalties;
  v_pool public.weekly_pools;
begin
  -- 1) Must be authenticated
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- 2) Determine week deadline (p_week_start_date parameter is actually the deadline)
  -- Note: The parameter name is legacy - it represents the deadline (next Monday), not when the week started
  if p_week_start_date is not null then
    v_week_start_date := p_week_start_date;  -- This is actually the deadline
  else
    -- Calculate current week's deadline (next Monday)
    v_week_start_date := CURRENT_DATE + (8 - EXTRACT(DOW FROM CURRENT_DATE)::int) % 7;
    IF EXTRACT(DOW FROM CURRENT_DATE) = 1 THEN
      -- If today is Monday, use next Monday
      v_week_start_date := CURRENT_DATE + 7;
    END IF;
  end if;

  -- 3) Fetch latest commitment for this user & week (if any)
  -- FIXED: Use week_end_date (deadline) to find commitments, not week_start_date
  -- week_end_date stores the deadline (next Monday), which guides settlements
  select c.*
  into v_commitment
  from public.commitments c
  where c.user_id = v_user_id
    and c.week_end_date = v_week_start_date
  order by c.created_at desc
  limit 1;

  -- 4) Fetch user_week_penalties row (if any)
  select uwp.*
  into v_user_week_pen
  from public.user_week_penalties uwp
  where uwp.user_id = v_user_id
    and uwp.week_start_date = v_week_start_date
  limit 1;

  -- 5) Fetch weekly_pools row (if any)
  select wp.*
  into v_pool
  from public.weekly_pools wp
  where wp.week_start_date = v_week_start_date
  limit 1;

  -- 6) Map to return fields with sensible defaults
  user_total_penalty_cents := coalesce(v_user_week_pen.total_penalty_cents, 0);
  user_status := coalesce(v_user_week_pen.status, 'none');
  user_max_charge_cents := coalesce(v_commitment.max_charge_cents, 0);
  pool_total_penalty_cents := coalesce(v_pool.total_penalty_cents, 0);
  pool_status := coalesce(v_pool.status, 'open');
  pool_instagram_post_url := v_pool.instagram_post_url;
  pool_instagram_image_url := v_pool.instagram_image_url;

  user_settlement_status := coalesce(v_user_week_pen.settlement_status, 'pending');
  charged_amount_cents := coalesce(v_user_week_pen.charged_amount_cents, 0);
  actual_amount_cents := coalesce(v_user_week_pen.actual_amount_cents, v_user_week_pen.total_penalty_cents, 0);
  refund_amount_cents := coalesce(v_user_week_pen.refund_amount_cents, 0);
  needs_reconciliation := coalesce(v_user_week_pen.needs_reconciliation, false);
  reconciliation_delta_cents := coalesce(v_user_week_pen.reconciliation_delta_cents, 0);
  reconciliation_reason := v_user_week_pen.reconciliation_reason;
  reconciliation_detected_at := v_user_week_pen.reconciliation_detected_at;

  week_grace_expires_at := coalesce(v_commitment.week_grace_expires_at, v_week_start_date + interval '1 day');
  week_end_date := v_week_start_date;

  return next;
  return;
end;
$$;

ALTER FUNCTION public."rpc_get_week_status"("p_week_start_date" date) OWNER TO "postgres";
