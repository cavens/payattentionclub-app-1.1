-- Check data for the week the function is trying to close (2025-11-17)

-- 1) Check commitments for week ending 2025-11-17
SELECT 
  id,
  user_id,
  week_start_date,
  week_end_date,
  status
FROM public.commitments
WHERE week_end_date = '2025-11-17'
ORDER BY created_at DESC;

-- 2) Check user_week_penalties for week 2025-11-17
SELECT 
  uwp.user_id,
  u.email,
  u.stripe_customer_id,
  uwp.total_penalty_cents,
  uwp.week_start_date
FROM public.user_week_penalties uwp
LEFT JOIN public.users u ON u.id = uwp.user_id
WHERE uwp.week_start_date = '2025-11-17';

-- 3) Check daily_usage for commitments ending 2025-11-17
SELECT 
  du.user_id,
  du.commitment_id,
  du.date,
  du.penalty_cents
FROM public.daily_usage du
WHERE du.commitment_id IN (
  SELECT id FROM public.commitments WHERE week_end_date = '2025-11-17'
)
ORDER BY du.date DESC;

-- 4) Check weekly_pool for 2025-11-17
SELECT 
  week_start_date,
  week_end_date,
  total_penalty_cents,
  status
FROM public.weekly_pools
WHERE week_start_date = '2025-11-17';


