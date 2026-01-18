-- ==============================================================================
-- Investigate Why Queue Entry Wasn't Created
-- ==============================================================================

-- 1. Check if queue entry exists for the new user
SELECT 
  'Queue Entry Check' AS check_type,
  id,
  user_id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  created_at,
  processed_at,
  CASE 
    WHEN id IS NOT NULL THEN '✅ Queue entry exists'
    ELSE '❌ No queue entry found'
  END AS result
FROM reconciliation_queue
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18';

-- 2. Check penalty record details
SELECT 
  'Penalty Record' AS check_type,
  id,
  user_id,
  week_start_date,
  needs_reconciliation,
  reconciliation_delta_cents,
  reconciliation_reason,
  reconciliation_detected_at,
  charged_amount_cents,
  actual_amount_cents,
  settlement_status,
  last_updated
FROM user_week_penalties
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18';

-- 3. Check when the penalty was last updated vs when reconciliation was detected
SELECT 
  'Timeline Check' AS check_type,
  reconciliation_detected_at,
  last_updated,
  CASE 
    WHEN reconciliation_detected_at = last_updated THEN '✅ Reconciliation detected during last update (should have created queue entry)'
    WHEN reconciliation_detected_at < last_updated THEN '⚠️ Reconciliation detected earlier, then updated again (queue entry might have been created then)'
    ELSE '❓ Timeline unclear'
  END AS result
FROM user_week_penalties
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
  AND week_start_date = '2026-01-18';

-- 4. Check if there are any queue entries for this user (any week, any status)
SELECT 
  'All Queue Entries for User' AS check_type,
  id,
  week_start_date,
  status,
  reconciliation_delta_cents,
  created_at,
  processed_at
FROM reconciliation_queue
WHERE user_id = '14a914ef-e323-4e0e-8701-8e008422f927'
ORDER BY created_at DESC;

