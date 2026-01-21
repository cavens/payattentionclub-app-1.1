-- ==============================================================================
-- Migration: Drop unused rpc_get_week_status_from_db function
-- Date: 2026-01-19
-- Purpose: Remove unused duplicate function that was never called
-- ==============================================================================
-- 
-- ISSUE:
-- The function rpc_get_week_status_from_db exists in the database but is never
-- used. The app only calls rpc_get_week_status. This duplicate function was
-- likely created during development and should be removed.
-- 
-- FIX:
-- Drop the unused function to clean up the database schema.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.rpc_get_week_status_from_db(date);

