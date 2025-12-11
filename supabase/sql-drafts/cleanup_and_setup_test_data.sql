-- Clean up all test data and repopulate
-- This deletes test users, commitments, daily_usage, user_week_penalties, and weekly_pools

-- 1) Delete test users (identified by is_test_user = true OR specific test UUIDs)
DELETE FROM public.users 
WHERE is_test_user = true 
   OR id IN (
     '11111111-1111-1111-1111-111111111111'::uuid,
     '22222222-2222-2222-2222-222222222222'::uuid,
     '33333333-3333-3333-3333-333333333333'::uuid
   );

-- 2) Delete all daily_usage (will be repopulated)
DELETE FROM public.daily_usage;

-- 3) Delete all user_week_penalties (will be repopulated)
DELETE FROM public.user_week_penalties;

-- 4) Delete all commitments (will be repopulated)
DELETE FROM public.commitments;

-- 5) Delete all weekly_pools (will be repopulated)
DELETE FROM public.weekly_pools;

-- 6) Now run the test data setup
SELECT rpc_setup_test_data();




