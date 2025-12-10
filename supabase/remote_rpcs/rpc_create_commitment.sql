CREATE OR REPLACE FUNCTION public.rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_apps_to_limit jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
declare
  v_user_id uuid := auth.uid();
  v_has_pm boolean;
  v_commitment_start_date date;
  v_deadline_ts timestamptz;
  v_minutes_remaining numeric;
  v_potential_overage numeric;
  v_risk_factor numeric;
  v_max_charge_cents integer;
  v_app_count integer;
  v_commitment_id uuid;
  v_result json;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select u.has_active_payment_method
    into v_has_pm
    from public.users u
    where u.id = v_user_id;

  if coalesce(v_has_pm, false) = false then
    raise exception 'User has no active payment method' using errcode = 'P0001';
  end if;

  v_commitment_start_date := current_date;
  v_deadline_ts := (p_deadline_date::timestamp at time zone 'America/New_York') + interval '12 hours';

  v_minutes_remaining := greatest(
    0,
    extract(epoch from (v_deadline_ts - now())) / 60.0
  );

  v_app_count := coalesce(jsonb_array_length(p_apps_to_limit->'app_bundle_ids'), 0)
               + coalesce(jsonb_array_length(p_apps_to_limit->'categories'), 0);

  v_risk_factor := 1.0 + 0.1 * v_app_count;

  v_potential_overage := greatest(0, v_minutes_remaining - p_limit_minutes);

  v_max_charge_cents :=
      v_potential_overage
    * p_penalty_per_minute_cents
    * v_risk_factor;

  if v_minutes_remaining > 0 then
    v_max_charge_cents := greatest(500, floor(v_max_charge_cents)::int);
  else
    v_max_charge_cents := 0;
  end if;

  insert into public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  values (
    p_deadline_date,
    p_deadline_date,
    0,
    'open'
  )
  on conflict (week_start_date) do nothing;

  insert into public.commitments (
    user_id,
    week_start_date,
    week_end_date,
    limit_minutes,
    penalty_per_minute_cents,
    apps_to_limit,
    status,
    monitoring_status,
    monitoring_revoked_at,
    autocharge_consent_at,
    max_charge_cents,
    created_at
  )
  values (
    v_user_id,
    v_commitment_start_date,
    p_deadline_date,
    p_limit_minutes,
    p_penalty_per_minute_cents,
    p_apps_to_limit,
    'pending',
    'ok',
    null,
    now(),
    v_max_charge_cents,
    now()
  )
  returning id into v_commitment_id;

  select row_to_json(c.*) into v_result
  from public.commitments c
  where c.id = v_commitment_id;

  return v_result;
end;
$$;


