-- ==============================================================================
-- CRITICAL SECURITY FIXES - APPLY IMMEDIATELY
-- ==============================================================================
-- 
-- These are critical security vulnerabilities that must be fixed.
-- Apply this SQL directly in the Supabase Dashboard SQL Editor.
-- 
-- Instructions:
-- 1. Go to Supabase Dashboard > SQL Editor
-- 2. Paste this entire file
-- 3. Click "Run"
-- ==============================================================================

-- ==============================================================================
-- Fix 1: rpc_preview_max_charge - Add authentication check
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_preview_max_charge(
    p_deadline_date date,
    p_limit_minutes integer,
    p_penalty_per_minute_cents integer,
    p_apps_to_limit jsonb DEFAULT '{}'::jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_deadline_ts timestamptz;
    v_app_count integer;
    v_max_charge_cents integer;
BEGIN
    -- Security: Require authentication for consistency with other RPC functions
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    
    -- Calculate deadline timestamp (noon EST on the deadline date)
    v_deadline_ts := (p_deadline_date::timestamp AT TIME ZONE 'America/New_York') + INTERVAL '12 hours';
    
    -- Count apps and categories
    v_app_count := COALESCE(jsonb_array_length(p_apps_to_limit->'app_bundle_ids'), 0)
                 + COALESCE(jsonb_array_length(p_apps_to_limit->'categories'), 0);
    
    -- Call the internal calculation function (single source of truth)
    v_max_charge_cents := public.calculate_max_charge_cents(
        v_deadline_ts,
        p_limit_minutes,
        p_penalty_per_minute_cents,
        v_app_count
    );
    
    -- Return as JSON
    RETURN json_build_object(
        'max_charge_cents', v_max_charge_cents,
        'max_charge_dollars', v_max_charge_cents / 100.0,
        'deadline_date', p_deadline_date,
        'limit_minutes', p_limit_minutes,
        'penalty_per_minute_cents', p_penalty_per_minute_cents,
        'app_count', v_app_count
    );
END;
$$;

-- Grant execute to authenticated users only (security requirement)
GRANT EXECUTE ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, jsonb) TO authenticated;

-- Revoke from anonymous users (security fix)
REVOKE EXECUTE ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, jsonb) FROM anon;

COMMENT ON FUNCTION public.rpc_preview_max_charge(date, integer, integer, jsonb) IS 
'Preview the max charge amount before creating a commitment.
Security: Requires authentication (SECURITY DEFINER function must verify user identity).';

-- ==============================================================================
-- Fix 2: rpc_setup_test_data - Restrict to test users only
-- ==============================================================================
-- IMPORTANT: This is a large function. The full secure version is in:
-- supabase/migrations/20251231001943_restrict_rpc_setup_test_data_to_test_users.sql
--
-- To apply Fix 2, you must:
-- 1. Open the file: supabase/migrations/20251231001943_restrict_rpc_setup_test_data_to_test_users.sql
-- 2. Copy its entire contents
-- 3. Run it in the SQL Editor
--
-- The key security changes in that file are:
-- - Added: v_user_id uuid := auth.uid();
-- - Added: Authentication check (IF v_user_id IS NULL THEN RAISE EXCEPTION)
-- - Added: Test user check (IF COALESCE(v_is_test_user, false) = false THEN RAISE EXCEPTION)

-- ==============================================================================
-- Verification Queries
-- ==============================================================================

-- Verify rpc_preview_max_charge requires authentication
SELECT 
    proname as function_name,
    prosecdef as is_security_definer,
    CASE 
        WHEN prosecdef THEN 'SECURITY DEFINER - Requires auth check in function body'
        ELSE 'SECURITY INVOKER'
    END as security_status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'rpc_preview_max_charge';

-- Check grants on rpc_preview_max_charge
SELECT 
    p.proname as function_name,
    r.rolname as role_name,
    CASE 
        WHEN has_function_privilege(r.oid, p.oid, 'EXECUTE') THEN 'YES'
        ELSE 'NO'
    END as can_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
CROSS JOIN pg_roles r
WHERE n.nspname = 'public' 
  AND p.proname = 'rpc_preview_max_charge'
  AND r.rolname IN ('authenticated', 'anon', 'anon')
ORDER BY r.rolname;

