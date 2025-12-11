-- ==============================================================================
-- List All Users in Database
-- ==============================================================================
-- Run this in Supabase SQL Editor to see all users
-- ==============================================================================

-- List all users from auth.users
SELECT 
    id,
    email,
    created_at,
    last_sign_in_at,
    email_confirmed_at
FROM auth.users
ORDER BY created_at DESC;

-- List users from public.users table
SELECT 
    id,
    email,
    created_at,
    stripe_customer_id,
    has_active_payment_method
FROM public.users
ORDER BY created_at DESC;

