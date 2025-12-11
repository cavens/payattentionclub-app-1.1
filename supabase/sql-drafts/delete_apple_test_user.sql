-- ==============================================================================
-- Delete Test User with Apple Email
-- ==============================================================================
-- This will find and delete any user with the Apple relay email pattern
-- Run this in Supabase SQL Editor for each environment
-- ==============================================================================

DO $$
DECLARE
    v_user_email TEXT := 'pythwk8m57@privaterelay.appleid.com';
    v_user_id UUID;
    v_deleted_payments INT := 0;
    v_deleted_daily_usage INT := 0;
    v_deleted_penalties INT := 0;
    v_deleted_commitments INT := 0;
    v_deleted_public_users INT := 0;
    v_deleted_auth_users INT := 0;
BEGIN
    -- Find user ID by email (try exact match first)
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = v_user_email;
    
    -- If not found, try case-insensitive or partial match
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id
        FROM auth.users
        WHERE LOWER(email) = LOWER(v_user_email)
           OR email LIKE '%pythwk8m57%'
           OR email LIKE '%privaterelay.appleid.com%';
    END IF;
    
    IF v_user_id IS NULL THEN
        RAISE NOTICE '❌ User not found with email: %', v_user_email;
        RAISE NOTICE '';
        RAISE NOTICE 'Listing all users in database:';
        FOR v_user_id IN SELECT id FROM auth.users ORDER BY created_at DESC LIMIT 10
        LOOP
            DECLARE
                v_email TEXT;
            BEGIN
                SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;
                RAISE NOTICE '  - %', v_email;
            END;
        END LOOP;
        RETURN;
    END IF;
    
    -- Get email for confirmation
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    
    RAISE NOTICE '✅ Found user: % (ID: %)', v_user_email, v_user_id;
    RAISE NOTICE '🗑️  Deleting user and all related data...';
    RAISE NOTICE '';
    
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
    GET DIAGNOSTICS v_deleted_public_users = ROW_COUNT;
    
    -- 6. Auth users (this will cascade)
    DELETE FROM auth.users WHERE id = v_user_id;
    GET DIAGNOSTICS v_deleted_auth_users = ROW_COUNT;
    
    RAISE NOTICE '✅ User deleted successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Deleted records:';
    RAISE NOTICE '   - Payments: %', v_deleted_payments;
    RAISE NOTICE '   - Daily usage: %', v_deleted_daily_usage;
    RAISE NOTICE '   - Penalties: %', v_deleted_penalties;
    RAISE NOTICE '   - Commitments: %', v_deleted_commitments;
    RAISE NOTICE '   - Public users: %', v_deleted_public_users;
    RAISE NOTICE '   - Auth users: %', v_deleted_auth_users;
    RAISE NOTICE '';
    RAISE NOTICE '🎉 You can now sign in fresh with Apple Sign-In!';
END $$;

