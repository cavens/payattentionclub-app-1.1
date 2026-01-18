-- ==============================================================================
-- Migration: Add week_end_timestamp column to commitments table
-- ==============================================================================
-- Purpose: Store precise deadline timestamp for testing mode while maintaining
--          backward compatibility with week_end_date (date only) for normal mode.
-- ==============================================================================

-- Add week_end_timestamp column (nullable, for testing mode precision)
ALTER TABLE public.commitments
ADD COLUMN IF NOT EXISTS week_end_timestamp timestamptz;

-- Add comment explaining the column
COMMENT ON COLUMN public.commitments.week_end_timestamp IS 
'Precise deadline timestamp (used in testing mode for 3-minute compressed timeline).
In normal mode, this is NULL and deadline is derived from week_end_date at noon ET.
In testing mode, this stores the exact deadline timestamp (creation + 3 minutes).';

-- Create index for efficient deadline queries
CREATE INDEX IF NOT EXISTS idx_commitments_week_end_timestamp 
ON public.commitments(week_end_timestamp) 
WHERE week_end_timestamp IS NOT NULL;



