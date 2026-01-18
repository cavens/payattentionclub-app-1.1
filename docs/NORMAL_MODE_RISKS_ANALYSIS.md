# Normal Mode Risks Analysis
## Issues That Testing Mode Cannot Catch

**Date**: 2026-01-15  
**Purpose**: Identify potential failures in normal mode (7-day weeks, 24-hour grace) that testing mode (3-minute weeks, 1-minute grace) cannot detect

---

## Critical Risks

### 1. ⚠️ **Daylight Saving Time (DST) Transitions**

**Risk Level**: HIGH  
**Why Testing Mode Misses It**: Testing mode completes in 3 minutes, never spans a DST transition

**Problem**:
- A week can span a DST transition (spring forward or fall back)
- DST changes occur in March (spring forward) and November (fall back)
- If a week starts in EST and ends in EDT (or vice versa), deadline calculations could be off by 1 hour

**Current Code Issue**:
```typescript
// supabase/functions/_shared/timing.ts:133
grace.setUTCDate(grace.getUTCDate() + 1);
```
This uses `setUTCDate()` which doesn't account for DST. If the week spans a DST transition:
- Monday 12:00 EST → Tuesday 12:00 EDT = 23 hours (spring forward)
- Monday 12:00 EDT → Tuesday 12:00 EST = 25 hours (fall back)

**Impact**:
- Grace period could expire 1 hour early or late
- Settlement could run at wrong time
- Users could be charged incorrectly

**Example Scenario**:
- Week starts: Monday, March 8, 2026 at 12:00 EST
- DST transition: Sunday, March 14, 2026 at 2:00 AM (spring forward)
- Grace deadline should be: Tuesday, March 10, 2026 at 12:00 EST
- But if calculated incorrectly: Could be 11:00 EST or 13:00 EDT

**Mitigation Needed**:
- Use timezone-aware date libraries (e.g., `date-fns-tz` or `luxon`)
- Calculate deadlines in ET timezone, not UTC
- Test with dates that span DST transitions

---

### 2. ⚠️ **Cron Job Timing Precision**

**Risk Level**: MEDIUM  
**Why Testing Mode Misses It**: Testing mode skips cron, uses manual triggers

**Problem**:
- Cron jobs can run slightly early or late (seconds to minutes off)
- What if cron runs at 11:59:59 ET vs 12:00:01 ET?
- Multiple cron executions if there's a delay or retry

**Impact**:
- Settlement could run before grace period expires
- Could charge worst case when actual should be charged
- Duplicate settlement runs if cron fires multiple times

**Example Scenario**:
- Cron scheduled: Tuesday 12:00:00 ET
- Actual execution: Tuesday 11:59:58 ET (2 seconds early)
- Grace period expires: Tuesday 12:00:00 ET
- Result: Settlement runs 2 seconds early, might charge worst case incorrectly

**Mitigation Needed**:
- Add grace period check at start of settlement function
- Use idempotency checks (already implemented: `shouldSkipBecauseSettled`)
- Add buffer time (e.g., run at 12:01 ET instead of 12:00 ET)

---

### 3. ⚠️ **Date Boundary Issues**

**Risk Level**: MEDIUM  
**Why Testing Mode Misses It**: Testing mode doesn't cross month/year boundaries

**Problem**:
- A week can span month boundaries (e.g., Jan 28 - Feb 4)
- A week can span year boundaries (e.g., Dec 29 - Jan 5)
- Date calculations using `setDate()` can fail at boundaries

**Current Code**:
```typescript
// supabase/functions/_shared/timing.ts:88
nextMonday.setDate(nextMonday.getDate() + daysUntilMonday);
```

**Impact**:
- If `setDate()` is called with invalid date (e.g., Feb 30), it might:
  - Roll over to next month (Feb 30 → Mar 2)
  - Throw an error
  - Produce incorrect dates

**Example Scenario**:
- Today: January 28, 2026 (Sunday)
- Calculate next Monday: Should be January 29, 2026
- But if calculation is off: Could be February 1, 2026 or January 22, 2026

**Mitigation Needed**:
- Use date libraries that handle boundaries correctly
- Test with dates at month/year boundaries
- Add validation for calculated dates

---

### 4. ⚠️ **Concurrency and Race Conditions**

**Risk Level**: MEDIUM  
**Why Testing Mode Misses It**: Testing mode is sequential, single-user

**Problem**:
- Multiple users settling at the same time
- Multiple syncs during grace period
- Settlement function called concurrently (cron + manual trigger)

**Known Issue** (from `docs/KNOWN_ISSUES.md`):
- Multiple concurrent syncs already identified
- 3-5 sync operations run concurrently
- Backend appears idempotent, but performance/cost impact

**Impact**:
- Database lock contention
- Race conditions in penalty calculations
- Duplicate charges if settlement runs twice
- Performance degradation at scale

**Example Scenario**:
- 100 users all sync at 11:59 PM ET on Monday
- Settlement runs at 12:00:01 ET on Tuesday
- Database locks on `user_week_penalties` table
- Some settlements fail, need retry

**Mitigation Needed**:
- Add database-level locking (SELECT FOR UPDATE)
- Use idempotency keys for settlement runs
- Implement retry logic with exponential backoff
- Monitor for concurrent execution patterns

---

### 5. ⚠️ **Payment Processing Delays**

**Risk Level**: MEDIUM  
**Why Testing Mode Misses It**: Testing mode completes before Stripe webhooks arrive

**Problem**:
- Stripe webhooks can be delayed (minutes to hours)
- Payment confirmations might not arrive before settlement completes
- Network timeouts during payment processing

**Impact**:
- Settlement might think payment failed when it succeeded
- Duplicate charges if webhook arrives late
- Reconciliation issues if payment status is unclear

**Example Scenario**:
- Settlement charges user at 12:00:01 ET
- Stripe processes payment, but webhook delayed
- Settlement function times out or errors
- Retry logic might charge again

**Mitigation Needed**:
- Add idempotency keys to Stripe charges
- Implement webhook retry logic
- Add timeout handling for payment processing
- Monitor webhook delivery times

---

### 6. ⚠️ **Long-Running Process Issues**

**Risk Level**: LOW  
**Why Testing Mode Misses It**: Testing mode is too fast for memory leaks/timeouts

**Problem**:
- Settlement function processes hundreds of users
- Memory usage accumulates over 7 days
- Database connections might timeout
- Edge Function execution time limits (60 seconds default)

**Impact**:
- Function timeout if processing too many users
- Memory leaks causing performance degradation
- Database connection pool exhaustion

**Example Scenario**:
- 1000 users need settlement
- Function processes 100 users per second
- Total time: 10 seconds (within limit)
- But if database is slow: Could timeout

**Mitigation Needed**:
- Implement pagination (process in batches)
- Add connection pooling
- Monitor execution times
- Add circuit breakers for slow operations

---

### 7. ⚠️ **Multiple Syncs During Grace Period**

**Risk Level**: LOW  
**Why Testing Mode Misses It**: Testing mode grace period is 1 minute, not enough time for multiple syncs

**Problem**:
- User could sync multiple times during 24-hour grace period
- Each sync updates `last_updated` timestamp
- Settlement checks `last_updated > deadline` to determine if synced

**Current Code**:
```typescript
// supabase/functions/bright-service/index.ts:268
const lastUpdated = new Date(penalty.last_updated);
return lastUpdated.getTime() > deadline.getTime();
```

**Impact**:
- If user syncs Monday 1:00 PM ET, then Tuesday 11:00 AM ET
- Settlement at 12:00 PM ET sees `last_updated = Tuesday 11:00 AM`
- Should charge actual (user synced before grace expired)
- But if logic is wrong: Could charge worst case

**Mitigation Needed**:
- Logic appears correct, but test with multiple syncs
- Ensure `last_updated` is always updated on sync
- Add logging to track sync timing

---

### 8. ⚠️ **Week Spanning DST Transition**

**Risk Level**: HIGH  
**Why Testing Mode Misses It**: Testing mode never spans a full week

**Problem**:
- Week could start in EST and end in EDT (or vice versa)
- Deadline calculation: Monday 12:00 EST
- Grace deadline: Tuesday 12:00 EDT (but is this correct?)

**Current Code Issue**:
```typescript
// supabase/functions/_shared/timing.ts:133
grace.setUTCDate(grace.getUTCDate() + 1);
```

This adds 1 day in UTC, but doesn't account for DST. If week spans DST:
- Spring forward: Grace period is 23 hours (not 24)
- Fall back: Grace period is 25 hours (not 24)

**Impact**:
- Grace period expires at wrong time
- Users charged incorrectly
- Legal/compliance issues if grace period is shorter than promised

**Mitigation Needed**:
- Use timezone-aware date calculations
- Test with weeks that span DST transitions
- Ensure grace period is always 24 hours in ET (not UTC)

---

## Summary Table

| Risk | Severity | Testing Mode Coverage | Mitigation Priority |
|------|----------|---------------------|-------------------|
| DST Transitions | HIGH | ❌ None | 🔴 Critical |
| Cron Timing Precision | MEDIUM | ❌ None | 🟡 Medium |
| Date Boundaries | MEDIUM | ❌ None | 🟡 Medium |
| Concurrency | MEDIUM | ⚠️ Partial | 🟡 Medium |
| Payment Delays | MEDIUM | ❌ None | 🟡 Medium |
| Long-Running Processes | LOW | ❌ None | 🟢 Low |
| Multiple Syncs | LOW | ⚠️ Partial | 🟢 Low |
| Week Spanning DST | HIGH | ❌ None | 🔴 Critical |

---

## Recommended Testing Strategy

### 1. **DST Transition Tests** (Critical)
- Test with weeks that span DST transitions:
  - March 8-15, 2026 (spring forward)
  - November 1-8, 2026 (fall back)
- Verify grace period is always 24 hours in ET
- Verify deadlines are calculated correctly

### 2. **Date Boundary Tests** (Medium)
- Test with weeks at month boundaries (Jan 28 - Feb 4)
- Test with weeks at year boundaries (Dec 29 - Jan 5)
- Verify date calculations don't fail

### 3. **Concurrency Tests** (Medium)
- Simulate 100+ concurrent users
- Test settlement running multiple times simultaneously
- Verify idempotency works correctly

### 4. **Cron Timing Tests** (Medium)
- Test settlement running 1 second early
- Test settlement running 1 second late
- Verify grace period check prevents premature charges

### 5. **Payment Processing Tests** (Medium)
- Simulate delayed Stripe webhooks
- Test payment timeouts
- Verify idempotency prevents duplicate charges

---

## Conclusion

Testing mode is excellent for validating logic and flow, but **cannot catch timing-related issues** that only appear over longer periods:

1. **DST transitions** are the highest risk - must be tested manually with specific dates
2. **Cron timing precision** needs manual testing or simulation
3. **Concurrency** needs load testing with multiple users
4. **Date boundaries** need edge case testing

**Recommendation**: Create a separate test suite for normal mode edge cases that:
- Uses real dates (not compressed timeline)
- Tests DST transitions explicitly
- Tests date boundaries
- Simulates concurrent users
- Tests cron timing edge cases



