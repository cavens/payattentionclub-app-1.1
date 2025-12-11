-- ==============================================================================
-- Clear ALL Test Data (DANGEROUS - Use with caution!)
-- ==============================================================================
-- This will delete ALL users and ALL data from the database
-- ⚠️  ONLY USE IN STAGING/TEST ENVIRONMENTS!
-- ==============================================================================

-- Uncomment and run these one by one if you want to clear everything:

-- 1. Delete all payments
-- DELETE FROM public.payments;

-- 2. Delete all daily usage
-- DELETE FROM public.daily_usage;

-- 3. Delete all user week penalties
-- DELETE FROM public.user_week_penalties;

-- 4. Delete all commitments
-- DELETE FROM public.commitments;

-- 5. Delete all weekly pools
-- DELETE FROM public.weekly_pools;

-- 6. Delete all public users
-- DELETE FROM public.users;

-- 7. Delete all auth users (this is the most dangerous!)
-- DELETE FROM auth.users;

-- Alternative: Use the RPC function for each user
-- SELECT rpc_delete_user_completely(email) FROM (SELECT email FROM auth.users) AS users;

