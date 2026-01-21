-- Drop existing function first (required when changing return type)
DROP FUNCTION IF EXISTS public.rpc_get_week_status(date);

CREATE OR REPLACE FUNCTION public.rpc_get_week_status(
  p_week_start_date date DEFAULT NULL
)
RETURNS TABLE (
  user_total_penalty_cents integer,
  user_status text,
  user_max_charge_cents integer,
  pool_total_penalty_cents integer,
  pool_status text,
  pool_instagram_post_url text,
  pool_instagram_image_url text,
  user_settlement_status text,
  charged_amount_cents integer,
  actual_amount_cents integer,
  refund_amount_cents integer,
  needs_reconciliation boolean,
  reconciliation_delta_cents integer,
  reconciliation_reason text,
  reconciliation_detected_at timestamptz,
  week_grace_expires_at timestamptz,
  week_end_date timestamptz,
  limit_minutes integer,
  penalty_per_minute_cents integer
)
LANGUAGE plpgsql
SECURITY DEFINER AS $$
declare
  v_user_id uuid := auth.uid();
  v_week_deadline date;
  v_commitment public.commitments;
  v_user_week_pen public.user_week_penalties;
  v_pool public.weekly_pools;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_week_start_date is not null then
    v_week_deadline := p_week_start_date;
  else
    v_week_deadline := current_date + (8 - extract(dow from current_date)::int) % 7;
    if extract(dow from current_date) = 1 then
      v_week_deadline := current_date + 7;
    end if;
  end if;

  select c.*
    into v_commitment
    from public.commitments c
    where c.user_id = v_user_id
      and c.week_end_date = v_week_deadline
    order by c.created_at desc
    limit 1;

  select uwp.*
    into v_user_week_pen
    from public.user_week_penalties uwp
    where uwp.user_id = v_user_id
      and uwp.week_start_date = v_week_deadline
    limit 1;

  select wp.*
    into v_pool
    from public.weekly_pools wp
    where wp.week_start_date = v_week_deadline
    limit 1;

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

  -- Convert week deadline + grace to Monday/Tuesday 12:00 PM ET
  week_end_date := (v_week_deadline::timestamptz at time zone 'America/New_York')
                   at time zone 'UTC'
                   + interval '12 hours';
  week_grace_expires_at :=
    coalesce(
      v_commitment.week_grace_expires_at,
      week_end_date + interval '24 hours'
    );

  -- Return commitment settings (limit_minutes and penalty_per_minute_cents)
  limit_minutes := coalesce(v_commitment.limit_minutes, 0);
  penalty_per_minute_cents := coalesce(v_commitment.penalty_per_minute_cents, 0);

  return next;
  return;
end;
$$;


