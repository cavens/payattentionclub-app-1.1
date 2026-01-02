-- ==============================================================================
-- Migration: Remove unused _internal_config table (security fix)
-- Date: 2026-01-01
-- Priority: CRITICAL - Security Fix
-- ==============================================================================
-- 
-- ISSUE: The _internal_config table contains sensitive configuration data in plain text
--        and has NO Row Level Security (RLS) enabled, making it accessible
--        to anyone with database access.
--
-- ANALYSIS:
--   - No functions currently use this table (call_weekly_close uses 
--     database settings instead)
--   - The table appears to be unused/legacy
--   - Contains sensitive configuration data that is exposed
--
-- FIX: Delete the table entirely since it's unused
--      This completely removes the security risk
--      If needed in the future, it can be recreated with proper security
-- ==============================================================================

-- Step 1: Verify the table exists before attempting to drop it
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = '_internal_config'
  ) THEN
    RAISE NOTICE 'Dropping unused _internal_config table...';
  ELSE
    RAISE NOTICE '_internal_config table does not exist, nothing to drop.';
  END IF;
END $$;

-- Step 2: Drop the table and all its data
-- This permanently removes the exposed sensitive data
DROP TABLE IF EXISTS public._internal_config CASCADE;

-- Step 3: Verify the table has been removed
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = '_internal_config'
  ) THEN
    RAISE EXCEPTION 'Failed to drop _internal_config table';
  ELSE
    RAISE NOTICE '✅ _internal_config table successfully removed';
  END IF;
END $$;

-- ==============================================================================
-- IMPORTANT: After running this migration:
-- 1. Verify the table no longer exists: 
--    SELECT tablename FROM pg_tables WHERE tablename = '_internal_config';
--    Should return 0 rows
-- 2. Verify call_weekly_close still works (it uses database settings, not this table)
-- ==============================================================================

