-- ==============================================================================
-- Fix Missing User Row in public.users
-- ==============================================================================
-- If a user exists in auth.users but not in public.users, this will create it
-- Run this in Supabase SQL Editor
-- ==============================================================================

-- Create missing user rows for all auth users that don't have a public.users entry
INSERT INTO public.users (id, email, created_at)
SELECT 
    au.id,
    au.email,
    au.created_at
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
WHERE pu.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- Verify the fix
SELECT 
    'Users in auth.users' as source,
    COUNT(*) as count
FROM auth.users
UNION ALL
SELECT 
    'Users in public.users' as source,
    COUNT(*) as count
FROM public.users;

-- Show any remaining mismatches
SELECT 
    au.id,
    au.email,
    au.created_at as auth_created_at,
    pu.created_at as public_created_at
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
WHERE pu.id IS NULL;

