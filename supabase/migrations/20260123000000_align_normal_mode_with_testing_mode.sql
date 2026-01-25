-- ==============================================================================
-- Migration: Align Normal Mode with Testing Mode Structure
-- ==============================================================================
-- Removes week_end_date column from commitments table.
-- Both testing and normal mode now use week_end_timestamp as primary source of truth.
-- This creates a unified structure where only time values differ, not the logic.
-- ==============================================================================

BEGIN;

-- Drop week_end_date column from commitments table
-- This column is no longer needed - week_end_timestamp is the primary source of truth
ALTER TABLE public.commitments DROP COLUMN IF EXISTS week_end_date;

-- Drop week_end_date column from weekly_pools table (if it exists)
-- weekly_pools uses week_start_date as primary key, week_end_date was redundant
ALTER TABLE public.weekly_pools DROP COLUMN IF EXISTS week_end_date;

COMMIT;

-- Add comment
COMMENT ON COLUMN public.commitments.week_end_timestamp IS 
'Primary source of truth for commitment deadline (timestamp).
Both testing and normal mode use this column.
- Testing mode: now + 4 minutes (precise timestamp)
- Normal mode: next Monday 12:00 ET (precise timestamp)
All lookups should use this column, not week_end_date (which is removed).';
