-- ==============================================================================
-- Reset Stuck Queue Entry
-- ==============================================================================
-- Use this to reset a queue entry that's stuck in 'processing' status
-- ==============================================================================

-- Reset the specific entry (replace with actual ID from Step 1)
UPDATE reconciliation_queue
SET status = 'pending', 
    processed_at = NULL,
    error_message = NULL
WHERE id = '5f6bc284-c57d-4c5e-9204-1d42c8ff694e';

-- Verify it was reset
SELECT id, user_id, week_start_date, status, processed_at, retry_count
FROM reconciliation_queue
WHERE id = '5f6bc284-c57d-4c5e-9204-1d42c8ff694e';

