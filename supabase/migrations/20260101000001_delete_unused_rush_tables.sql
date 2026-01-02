-- ==============================================================================
-- Migration: Delete unused RUSH project tables from production
-- Date: 2026-01-01
-- Priority: Security Fix - Remove Unrestricted Tables
-- ==============================================================================
-- 
-- ISSUE: The following tables exist in production and have NO Row Level Security (RLS):
--   - insurance_policies
--   - insurance_verification_jobs
--   - wristbands
--
-- These tables are from the RUSH project and are not used by PayAttentionClub.
-- They are unrestricted and accessible without authentication.
--
-- FIX: Delete all three tables entirely
-- ==============================================================================

-- Step 1: Drop insurance_verification_jobs first (has foreign key to insurance_policies)
DROP TABLE IF EXISTS public.insurance_verification_jobs CASCADE;

-- Step 2: Drop insurance_policies
DROP TABLE IF EXISTS public.insurance_policies CASCADE;

-- Step 3: Drop wristbands
DROP TABLE IF EXISTS public.wristbands CASCADE;

-- Step 4: Verify all tables have been removed
DO $$
DECLARE
    remaining_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO remaining_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name IN ('insurance_policies', 'insurance_verification_jobs', 'wristbands');
    
    IF remaining_count > 0 THEN
        RAISE EXCEPTION 'Failed to delete all tables. % table(s) still exist.', remaining_count;
    ELSE
        RAISE NOTICE '✅ All RUSH project tables successfully removed';
    END IF;
END $$;

-- ==============================================================================
-- IMPORTANT: After running this migration:
-- 1. Verify the tables no longer exist:
--    SELECT tablename FROM pg_tables 
--    WHERE tablename IN ('insurance_policies', 'insurance_verification_jobs', 'wristbands');
--    Should return 0 rows
-- ==============================================================================

