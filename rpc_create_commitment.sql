CREATE OR REPLACE FUNCTION public."rpc_create_commitment"("p_deadline_date" date, "p_limit_minutes" integer, "p_penalty_per_minute_cents" integer, "p_apps_to_limit" jsonb) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
  -- 1) Must be authenticated
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  -- 2) Check that user has an active payment method
  select u.has_active_payment_method
  into v_has_pm
  from public.users u
  where u.id = v_user_id;

  if coalesce(v_has_pm, false) = false then
    raise exception 'User has no active payment method' using errcode = 'P0001';
  end if;

  -- 3) The commitment starts NOW (when user commits) and ends on the deadline
  v_commitment_start_date := current_date;  -- Commitment starts today
  v_deadline_ts := (p_deadline_date::timestamp at time zone 'America/New_York') + interval '12 hours';
  
  -- 4) Compute minutes remaining until deadline (minimum 0)
  v_minutes_remaining := greatest(
    0,
    extract(epoch from (v_deadline_ts - now())) / 60.0
  );

  -- 5) Extract app count from JSONB object
  -- p_apps_to_limit is a JSONB object: {"app_bundle_ids": [], "categories": []}
  -- We need to access the nested arrays and sum their lengths
  v_app_count := coalesce(jsonb_array_length(p_apps_to_limit->'app_bundle_ids'), 0)
               + coalesce(jsonb_array_length(p_apps_to_limit->'categories'), 0);

  -- 6) Simple risk factor based on number of apps/categories
  v_risk_factor := 1.0 + 0.1 * v_app_count;

  -- 7) Compute max_charge_cents based on potential overage minutes
  v_potential_overage := greatest(0, v_minutes_remaining - p_limit_minutes);
  v_max_charge_cents :=
      v_potential_overage
    * p_penalty_per_minute_cents
    * v_risk_factor;

  -- Enforce a $5 minimum authorization hold unless there is literally no time left
  if v_max_charge_cents > 0 then
    v_max_charge_cents := greatest(500, floor(v_max_charge_cents)::int);
  else
    v_max_charge_cents := 0;
  end if;

  -- 8) Ensure weekly pool for this week exists
  -- Use the deadline date as the pool identifier
  -- This groups all commitments that end on the same Monday
  insert into public.weekly_pools (
    week_start_date,
    week_end_date,
    total_penalty_cents,
    status
  )
  values (
    p_deadline_date,    -- Use deadline as pool identifier
    p_deadline_date,    -- Same as deadline (pool ends when commitments end)
    0,
    'open'
  )
  on conflict (week_start_date) do nothing;

  -- 9) Insert commitment row and get the ID
  -- IMPORTANT: The column names week_start_date and week_end_date are legacy naming
  --   - week_start_date: Actually stores when the commitment started (current_date, when user commits)
  --   - week_end_date: Actually stores the deadline (p_deadline_date, next Monday before noon)
  -- The commitment starts NOW (current_date) and ends on the deadline
  insert into public.commitments (
    user_id,
    week_start_date,  -- Legacy name: Actually the commitment start date (when user commits)
    week_end_date,    -- Legacy name: Actually the deadline (next Monday before noon)
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
    v_commitment_start_date,  -- Commitment starts NOW (when user commits)
    p_deadline_date,          -- Commitment ends on deadline (next Monday before noon)
    p_limit_minutes,
    p_penalty_per_minute_cents,
    p_apps_to_limit,
    'pending',      -- or 'active' depending on your flow
    'ok',
    null,
    now(),
    v_max_charge_cents,
    now()
  )
  returning id into v_commitment_id;

  -- 10) Fetch the full commitment row and convert to JSON
  select row_to_json(c.*) into v_result
  from public.commitments c
  where c.id = v_commitment_id;

  -- 11) Return JSON result
  return v_result;
end;
$$;


ALTER FUNCTION public."rpc_create_commitment"("p_deadline_date" date, "p_limit_minutes" integer, "p_penalty_per_minute_cents" integer, "p_apps_to_limit" jsonb) OWNER TO "postgres";
