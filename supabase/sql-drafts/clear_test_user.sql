-- ==============================================================================
-- Clear Test User by Email
-- ==============================================================================
-- Run this in Supabase SQL Editor to delete a specific test user
-- Replace 'pythwk8m57@privaterelay.appleid.com' with the actual email
-- ==============================================================================

-- Set the email to delete
DO $$
DECLARE
    v_user_email TEXT := 'pythwk8m57@privaterelay.appleid.com';
    v_user_id UUID;
    v_deleted_payments INT := 0;
    v_deleted_daily_usage INT := 0;
    v_deleted_penalties INT := 0;
    v_deleted_commitments INT := 0;
BEGIN
    -- Find user ID by email
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = v_user_email;
    
    IF v_user_id IS NULL THEN
        RAISE NOTICE 'User not found with email: %', v_user_email;
        RETURN;
    END IF;
    
    RAISE NOTICE 'Found user: % (ID: %)', v_user_email, v_user_id;
    
    -- Delete in order (respecting foreign keys)
    -- 1. Payments
    DELETE FROM public.payments WHERE user_id = v_user_id;
    GET DIAGNOSTICS v_deleted_payments = ROW_COUNT;
    
    -- 2. Daily usage
    DELETE FROM public.daily_usage WHERE user_id = v_user_id;
    GET DIAGNOSTICS v_deleted_daily_usage = ROW_COUNT;
    
    -- 3. User week penalties
    DELETE FROM public.user_week_penalties WHERE user_id = v_user_id;
    GET DIAGNOSTICS v_deleted_penalties = ROW_COUNT;
    
    -- 4. Commitments
    DELETE FROM public.commitments WHERE user_id = v_user_id;
    GET DIAGNOSTICS v_deleted_commitments = ROW_COUNT;
    
    -- 5. Public users table
    DELETE FROM public.users WHERE id = v_user_id;
    
    -- 6. Auth users (this will cascade)
    DELETE FROM auth.users WHERE id = v_user_id;
    
    RAISE NOTICE '✅ User deleted successfully!';
    RAISE NOTICE '   Payments: %', v_deleted_payments;
    RAISE NOTICE '   Daily usage: %', v_deleted_daily_usage;
    RAISE NOTICE '   Penalties: %', v_deleted_penalties;
    RAISE NOTICE '   Commitments: %', v_deleted_commitments;
END $$;


