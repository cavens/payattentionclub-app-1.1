-- Check what's actually in the database

-- 1) Check all commitments
SELECT 
  id,
  user_id,
  week_start_date,
  week_end_date,
  status,
  created_at
FROM public.commitments
ORDER BY created_at DESC
LIMIT 10;

-- 2) Check all users with their Stripe IDs
SELECT 
  id,
  email,
  stripe_customer_id,
  has_active_payment_method,
  is_test_user
FROM public.users
ORDER BY created_at DESC
LIMIT 10;

-- 3) Check all user_week_penalties
SELECT 
  user_id,
  week_start_date,
  total_penalty_cents,
  status
FROM public.user_week_penalties
ORDER BY last_updated DESC
LIMIT 10;

-- 4) Check all weekly_pools
SELECT 
  week_start_date,
  week_end_date,
  total_penalty_cents,
  status
FROM public.weekly_pools
ORDER BY week_start_date DESC
LIMIT 10;


