# Normal Mode Bug Risk Analysis

## Overview

This document identifies potential bugs that could occur in **normal mode** but might not be detected in **testing mode** due to timing differences, scale differences, or edge cases.

---

## Critical Differences Between Modes

| Aspect | Testing Mode | Normal Mode | Risk Level |
|--------|--------------|-------------|------------|
| **Week Duration** | 3 minutes | 7 days | 🔴 High |
| **Grace Period** | 1 minute | 24 hours | 🔴 High |
| **Settlement Schedule** | Every 1-2 minutes | Weekly (Tuesday 12:00 ET) | 🟡 Medium |
| **Deadline Type** | `week_end_timestamp` (precise) | `week_end_date` (date only) | 🟡 Medium |
| **Data Volume** | Small (few commitments) | Large (many commitments) | 🟡 Medium |
| **Time Zones** | Less critical | Critical (Monday 12:00 ET) | 🔴 High |

---

## 🔴 High-Risk Areas

### 1. Time Zone Handling

**Risk**: Normal mode uses fixed schedule (Monday 12:00 ET), testing mode uses relative timestamps.

**Potential Bugs**:
- **Bug**: Time zone conversion errors when calculating Monday 12:00 ET
  - **Testing Mode**: Uses `created_at + 3 minutes` (UTC, no timezone issues)
  - **Normal Mode**: Must calculate "previous Monday 12:00 ET" from any timezone
  - **Impact**: Wrong deadline dates, settlement runs at wrong time
  - **Detection**: Hard to test in testing mode (no timezone calculations)

**Test**:
```sql
-- Test Monday calculation from different timezones
SELECT 
  NOW() AS current_time,
  -- Should calculate previous Monday 12:00 ET correctly
  -- Test from different times of week
```

**Mitigation**:
- ✅ Verify `resolveWeekTarget()` handles timezone correctly
- ✅ Test with commitments created at different times
- ✅ Verify settlement cron runs at correct time (Tuesday 12:00 ET)

---

### 2. Week Boundary Calculations

**Risk**: Normal mode uses fixed weekly boundaries (Monday to Monday), testing mode uses dynamic boundaries.

**Potential Bugs**:
- **Bug**: Commitment created on Monday 11:59 AM ET gets wrong week_end_date
  - **Testing Mode**: Always uses `created_at + 3 minutes` (no boundary issues)
  - **Normal Mode**: Must determine which Monday the commitment belongs to
  - **Impact**: Commitment assigned to wrong week, settlement timing wrong
  - **Detection**: Only occurs at week boundaries (Monday 12:00 ET)

**Test**:
```sql
-- Test commitments created at different times relative to Monday 12:00 ET
-- Create test commitment just before Monday 12:00 ET
-- Create test commitment just after Monday 12:00 ET
-- Verify both get correct week_end_date
```

**Mitigation**:
- ✅ Test commitment creation at week boundaries
- ✅ Verify `week_end_date` calculation is correct
- ✅ Test edge cases: Monday 11:59 AM, Monday 12:01 PM

---

### 3. Grace Period Expiration

**Risk**: Normal mode has 24-hour grace period, testing mode has 1-minute grace period.

**Potential Bugs**:
- **Bug**: User syncs data 23 hours after deadline, but system thinks grace period expired
  - **Testing Mode**: 1-minute grace period (easy to test, hard to miss)
  - **Normal Mode**: 24-hour grace period (timing errors more likely)
  - **Impact**: User charged incorrectly, reconciliation issues
  - **Detection**: Only occurs with 24-hour calculations

**Test**:
```sql
-- Test grace period calculations
SELECT 
  week_end_date,
  grace_period_end_date,
  grace_period_end_date - week_end_date AS grace_duration,
  CASE 
    WHEN grace_period_end_date - week_end_date = INTERVAL '24 hours' THEN '✅ Correct'
    ELSE '❌ Wrong duration'
  END AS status
FROM user_week_penalties
WHERE week_end_date >= CURRENT_DATE - INTERVAL '7 days';
```

**Mitigation**:
- ✅ Verify `getGraceDeadline()` returns 24 hours in normal mode
- ✅ Test grace period expiration logic
- ✅ Verify settlement waits for grace period

---

### 4. Settlement Batch Processing

**Risk**: Normal mode processes many commitments at once (weekly batch), testing mode processes few commitments frequently.

**Potential Bugs**:
- **Bug**: Settlement fails partway through batch, leaving some commitments unprocessed
  - **Testing Mode**: Processes 1-2 commitments at a time (failures are isolated)
  - **Normal Mode**: Processes hundreds of commitments (partial failures possible)
  - **Impact**: Some users charged, others not, inconsistent state
  - **Detection**: Only occurs with large batches

**Test**:
```sql
-- Check for commitments that should be settled but aren't
SELECT 
  COUNT(*) AS unprocessed_commitments,
  MIN(week_end_date) AS oldest_unprocessed,
  MAX(week_end_date) AS newest_unprocessed
FROM commitments
WHERE status = 'active'
  AND week_end_date < CURRENT_DATE - INTERVAL '2 days'  -- Should be settled
  AND grace_period_end_date < NOW();  -- Grace period expired
```

**Mitigation**:
- ✅ Use transactions for batch processing
- ✅ Implement idempotency (can retry safely)
- ✅ Add logging for partial failures
- ✅ Monitor for stuck commitments

---

### 5. Reconciliation Timing

**Risk**: Normal mode has 24-hour window for reconciliation, testing mode has 1-minute window.

**Potential Bugs**:
- **Bug**: User syncs data 25 hours after settlement, reconciliation not triggered
  - **Testing Mode**: 1-minute window (easy to test)
  - **Normal Mode**: 24-hour window (edge cases at boundaries)
  - **Impact**: User doesn't get refund/charge adjustment
  - **Detection**: Only occurs with longer time windows

**Test**:
```sql
-- Check for penalties that need reconciliation but don't have queue entry
SELECT 
  p.penalty_id,
  p.user_id,
  p.week_end_date,
  p.settlement_status,
  p.actual_amount_cents,
  p.charged_amount_cents,
  CASE 
    WHEN p.actual_amount_cents != p.charged_amount_cents 
      AND p.settlement_status = 'settled'
      AND NOT EXISTS (
        SELECT 1 FROM reconciliation_queue rq 
        WHERE rq.user_id = p.user_id 
          AND rq.week_end_date = p.week_end_date
      )
    THEN '❌ Needs reconciliation but no queue entry'
    ELSE '✅ OK'
  END AS status
FROM user_week_penalties p
WHERE p.week_end_date >= CURRENT_DATE - INTERVAL '14 days'
  AND p.settlement_status = 'settled'
LIMIT 10;
```

**Mitigation**:
- ✅ Test reconciliation detection with various sync times
- ✅ Verify `rpc_sync_daily_usage` detects reconciliation correctly
- ✅ Use `rpc_detect_missed_reconciliations` to catch missed cases

---

## 🟡 Medium-Risk Areas

### 6. Data Volume and Performance

**Risk**: Normal mode processes more data, testing mode processes minimal data.

**Potential Bugs**:
- **Bug**: Settlement query times out with large dataset
  - **Testing Mode**: Few commitments, queries fast
  - **Normal Mode**: Many commitments, queries slow
  - **Impact**: Settlement fails, cron job timeout
  - **Detection**: Only occurs with large datasets

**Test**:
```sql
-- Check query performance
EXPLAIN ANALYZE
SELECT * FROM commitments
WHERE week_end_date = '2026-01-13'  -- Example Monday
  AND status = 'active';
```

**Mitigation**:
- ✅ Add database indexes on `week_end_date`, `status`
- ✅ Test with realistic data volumes
- ✅ Monitor query performance
- ✅ Add query timeouts

---

### 7. Concurrent User Activity

**Risk**: Normal mode has many concurrent users, testing mode has few.

**Potential Bugs**:
- **Bug**: Race condition when multiple users sync simultaneously
  - **Testing Mode**: Sequential operations, no concurrency issues
  - **Normal Mode**: Concurrent syncs, potential race conditions
  - **Impact**: Data corruption, incorrect calculations
  - **Detection**: Only occurs under load

**Test**:
- Simulate concurrent syncs
- Check for database locks
- Verify transaction isolation

**Mitigation**:
- ✅ Use database transactions
- ✅ Use `FOR UPDATE SKIP LOCKED` for queue processing
- ✅ Test with concurrent requests

---

### 8. Edge Function Cold Starts

**Risk**: Normal mode has infrequent calls (weekly), testing mode has frequent calls (every 1-2 min).

**Potential Bugs**:
- **Bug**: Edge Function cold start causes timeout or error
  - **Testing Mode**: Functions stay warm (frequent calls)
  - **Normal Mode**: Functions cold start (infrequent calls)
  - **Impact**: Settlement fails on first run
  - **Detection**: Only occurs after cold start

**Test**:
- Wait for function to go cold (no calls for 10+ minutes)
- Trigger settlement
- Verify it works correctly

**Mitigation**:
- ✅ Test cold start behavior
- ✅ Add retry logic
- ✅ Monitor function execution time

---

## 🟢 Low-Risk Areas

### 9. Date Format Handling

**Risk**: Normal mode uses date-only fields, testing mode uses timestamps.

**Potential Bugs**:
- **Bug**: Date comparison errors (timezone, format)
  - **Testing Mode**: Uses precise timestamps
  - **Normal Mode**: Uses date-only fields
  - **Impact**: Wrong week calculations
  - **Detection**: Edge cases with date boundaries

**Mitigation**:
- ✅ Use consistent date formats
- ✅ Test date comparisons
- ✅ Verify timezone handling

---

## Testing Strategy

### Phase 1: Mode Transition Testing

1. **Toggle to Normal Mode**
   - Verify both locations update
   - Run validation function
   - Check cron jobs

2. **Test Normal Mode Behavior**
   - Create commitment in normal mode
   - Verify deadline is 7 days (not 3 minutes)
   - Verify grace period is 24 hours (not 1 minute)
   - Wait for settlement (or trigger manually)
   - Verify settlement uses correct timing

3. **Toggle Back to Testing Mode**
   - Verify both locations update
   - Run validation function
   - Test testing mode behavior restored

### Phase 2: Normal Mode Specific Tests

1. **Time Zone Tests**
   - Create commitments at different times
   - Verify Monday 12:00 ET calculation
   - Test week boundary edge cases

2. **Batch Processing Tests**
   - Create multiple commitments
   - Trigger settlement
   - Verify all processed correctly

3. **Grace Period Tests**
   - Test sync at different times during grace period
   - Test sync after grace period
   - Verify reconciliation detection

### Phase 3: Edge Case Tests

1. **Week Boundary Tests**
   - Commitment created Monday 11:59 AM ET
   - Commitment created Monday 12:01 PM ET
   - Verify correct week assignment

2. **Concurrent Operation Tests**
   - Multiple users sync simultaneously
   - Settlement runs while users sync
   - Verify no data corruption

3. **Error Recovery Tests**
   - Simulate partial settlement failure
   - Verify retry logic works
   - Check for stuck commitments

---

## Automated Test Script

Create a script that:
1. Toggles to normal mode
2. Creates test commitment
3. Verifies timing (7 days, 24 hours)
4. Triggers settlement
5. Verifies settlement behavior
6. Toggles back to testing mode
7. Verifies testing mode restored

---

## Monitoring Recommendations

1. **Daily Validation**
   - Run `rpc_validate_mode_consistency()` daily
   - Alert if `valid: false`

2. **Settlement Monitoring**
   - Log settlement execution time
   - Monitor for failures
   - Check for stuck commitments

3. **Reconciliation Monitoring**
   - Check for missed reconciliations
   - Monitor reconciliation queue
   - Alert on queue backlog

---

## Next Steps

1. ✅ Create validation function
2. ⏳ Create automated test script
3. ⏳ Test mode transitions
4. ⏳ Test normal mode specific scenarios
5. ⏳ Set up monitoring

