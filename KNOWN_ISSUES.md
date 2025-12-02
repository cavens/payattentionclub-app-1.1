# Known Issues & Bugs

This document tracks known bugs and issues that are not critical enough to block development but should be addressed in the future.

---

## Phase 3: Multiple Concurrent Syncs Issue

**Status**: Known Issue - Non-Critical  
**Severity**: Medium (Performance/Cost)  
**Date Identified**: 2025-11-28  
**Phase**: Phase 3 - Sync Manager Implementation

### Description

Multiple concurrent calls to `syncDailyUsage()` are executing simultaneously instead of being serialized. When `syncToBackend()` is called multiple times (e.g., from app launch, foreground, and multiple views), 3-5 sync operations run concurrently, all syncing the same data.

### Symptoms

- Multiple sync operations complete for the same entries
- All syncs share the same call ID (suspicious - should be unique UUIDs)
- Logs show multiple "✅ Successfully synced" messages for the same data
- Both `UsageSyncManager` coordinator and `BackendClient` guards are not preventing concurrent execution

### Impact

**Functional**: ✅ None - Syncs complete successfully, data reaches backend, entries marked as synced  
**Performance**: ⚠️ Medium - 3-5x more network requests and database writes than necessary  
**Cost**: ⚠️ Medium - More Supabase RPC calls = higher costs at scale  
**User Experience**: ✅ None - Happens in background, users don't notice  
**Data Integrity**: ✅ None - Backend appears idempotent, no data corruption observed

### Root Cause Analysis

**Attempted Solutions**:
1. ✅ `UsageSyncManager` uses `SyncCoordinator` with serial `DispatchQueue` - **Partially working** (allows 6 concurrent calls through)
2. ❌ `BackendClient` guard using `withCheckedContinuation` + async queue - Race condition, multiple calls get through
3. ❌ Attempted `NSLock` - Cannot use in async context (Swift 6)
4. ❌ Changed to `sync` dispatch for atomic check-and-set - **Still not working** (6 calls all see `isSyncing: false` simultaneously)

**Current Implementation**:
- `UsageSyncManager` coordinator: Uses serial `DispatchQueue` with `withCheckedContinuation` - **Partially working** (allows 6 concurrent calls)
- `BackendClient` guard: Uses `sync` dispatch on serial queue for atomic check-and-set - **Not working** (6 calls all see `isSyncing: false` simultaneously)

**Latest Test Results (2025-11-28 23:36)**:
- 6 concurrent `syncToBackend()` calls all got `canStart=true` from coordinator
- All 6 calls share same call ID `6EE719D9` (should be unique)
- All 6 calls see `isSyncing: false` in BackendClient guard simultaneously
- All 6 syncs complete successfully
- Root cause: Both guards failing - coordinator allows 6 through, BackendClient allows all 6 through

**Suspected Issue**:
- Race condition where multiple continuations are created before queue processes them
- All syncs getting same call ID suggests they might be from same execution context
- Missing initial logs (`🔵 syncDailyUsage() called`) suggests buffering/filtering issue

### Code Locations

- `UsageSyncManager.swift`: `syncToBackend()` method, `SyncCoordinator` class
- `BackendClient.swift`: `syncDailyUsage()` method, static `_isSyncingDailyUsage` flag and `_syncQueue`

### When to Fix

**Priority**: Medium  
**Suggested Timeline**: After Phase 4+ implementation, or when:
- Costs become an issue
- Performance degrades noticeably
- Data inconsistencies appear
- Dedicated optimization time available

### Proposed Fix

**Root Cause Analysis Needed**:
- Why does `sync` dispatch allow multiple calls to see `isSyncing: false` simultaneously?
- Why do all calls share the same call ID? (UUID generation issue?)
- Why does coordinator allow 6 calls through instead of 1?

**Potential Solutions**:
1. **Use Swift `actor`** for both `UsageSyncManager` and `BackendClient` sync coordination (async-safe)
2. **Single global sync coordinator** - Remove duplicate guards, use one authoritative coordinator
3. **OSAllocatedUnfairLock** - Modern Swift concurrency primitive (iOS 16+)
4. **Semaphore-based approach** - Use `DispatchSemaphore` for serialization
5. **Investigate call ID issue** - Why are UUIDs not unique? Could indicate deeper problem

**Recommended Approach**: Use Swift `actor` - designed for this exact use case (async-safe state management)

### Testing

To verify fix:
1. Trigger multiple sync calls simultaneously (app launch + foreground + manual)
2. Check logs for:
   - Only ONE sync operation completing
   - Other calls being rejected or queued
   - Unique call IDs for each attempt
3. Verify backend receives only one sync request per entry

---

## Phase 2: Weekly Grace Window Needs Pre-Week Buffer

**Status**: Known Issue - UX/Behavioral  
**Severity**: Low (User Expectation)  
**Date Identified**: 2025-12-01  
**Phase**: Phase 2 - Commitment Tracking

### Description

Weekly commitments currently apply a **24-hour grace period only *after* the week ends**. We now need a **2–4 hour buffer *before* the week ends** during which usage should **not** be counted. This ensures users get an automatic “cool down” window leading into the week transition without impacting their streak.

### Symptoms

- Usage recorded during the final hours of the week still affects the outgoing week totals.
- Users see last-minute usage reflected in the dashboard when it should be ignored.
- Grace logic does not match current product expectations (pre-week buffer missing).

### Impact

**Functional**: ⚠️ Low - Tracking still works but doesn’t follow desired grace rules  
**User Experience**: ⚠️ Medium - Users may feel penalized for last-minute usage  
**Data Integrity**: ✅ None - Data is accurate, just counted when it shouldn’t be  
**Product Consistency**: ⚠️ Medium - Behavior differs from documented UX

### Proposed Fix

1. Update commitment evaluation logic to treat **the final 2–4 hours of the week as grace time** (usage ignored).
2. Maintain the existing **24-hour post-week grace period**.
3. Ensure UI labels/tooltips reflect the expanded window.
4. Add automated tests covering both pre- and post-week grace windows.

### Code Locations

- `UsageTracker.swift` (weekly window calculations)
- `CommitmentEvaluator.swift` or equivalent logic handling grace periods
- Any UI components reflecting “time remaining” for the week

### Testing

1. Simulate time within final 2–4 hours of a weekly window: verify usage is ignored.
2. Verify usage outside the buffer still counts.
3. Confirm 24-hour post-week grace still works.

---

## Future Issues

_Add new issues here as they are discovered..._

---

## Phase 1: Email Contact Limitation with Sign in with Apple

**Status**: Known Issue - Potential Product Limitation  
**Severity**: Medium (Growth & Support)  
**Date Identified**: 2025-12-01  
**Phase**: Phase 1 - Authentication & Onboarding

### Description

Users signing in exclusively via “Sign in with Apple” provide randomized, pseudonymous relay email addresses (e.g., `abcd1234@privaterelay.appleid.com`). We currently **do not collect a real contact email**, so:
- Transactional emails (weekly summaries, nudges) may be filtered or ignored.
- We can’t guarantee we can reach users outside the app.
- Support follow-ups are difficult when Apple relay is disabled or rate-limited.

### Symptoms

- Email campaigns (Loops) only reach Apple relay addresses.
- Some users report never receiving reminders.
- We cannot correlate app accounts with real customer support tickets.

### Impact

**Product**: ⚠️ Medium – reduces engagement with email reminders and nudges.  
**Support**: ⚠️ Medium – harder to reach customers proactively.  
**Compliance**: ✅ None – still compliant, but Apple may throttle relays.  
**Data**: ✅ None – no data loss, just communication friction.

### Proposed Fix

1. Prompt users (post-onboarding) to optionally share their real email address for reminders/support.  
2. Store it securely in Supabase and mark whether the user opted in.  
3. Update backend/email logic to prefer the real email when available, fallback to Apple relay otherwise.  
4. Add UI copy explaining why the primary email improves reminders.  
5. Consider making this mandatory for features that rely on external communication.

### Code/Feature Touchpoints

- `AuthorizationView.swift` (post-login UI)  
- `BackendClient` / Supabase schema (extra user field for contact email + consent flag)  
- Reminder scheduling logic (Loops template data)  
- Account settings view (allow editing/removal)

### Testing

- Sign in via Apple, add a real email, verify Supabase stores and Loops sends to the correct address.  
- Ensure opt-out/respect user deletion of the real email.  
- Confirm backend falls back to Apple relay if no real email exists.

---

## Notes

- All issues documented here are **non-blocking** - development can continue
- Issues are prioritized by severity and impact
- Fix timeline is flexible and based on available resources

