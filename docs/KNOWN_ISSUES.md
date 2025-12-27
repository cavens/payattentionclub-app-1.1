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

## Phase 4C: Reconciliation Guardrails Depend on Operator Discipline

**Status**: Known Issue – Operational Risk  
**Severity**: Medium (Financial/Support)  
**Date Identified**: 2025-12-07  
**Phase**: Phase 4C – Integration & Guardrails

### Description

The `settlement-reconcile` scheduler can be misconfigured (e.g., larger payloads, no dry run) which increases the blast radius if Stripe refunds/charges have bugs. The safe-ops steps live in `supabase/functions/settlement-reconcile/README.md`, but they are easy to skip when someone new touches the cron or runs it manually.

### Symptoms / Risks

- Cron body is edited to include a high `limit`, so one run can touch hundreds of rows.
- Operators trigger the Edge Function manually without doing a dry run first.
- Team members do not have the curl snippet handy and improvise calls, risking malformed payloads.

### Impact

**Financial**: ⚠️ Medium – unintended bulk refunds/charges, Stripe disputes.  
**Support**: ⚠️ Medium – flood of user questions if reconciliation misfires.  
**Product**: ✅ None – feature works, risk comes from ops process.  
**Data Integrity**: ⚠️ Low – incorrect settlement rows until manual cleanup.

### Mitigation / Guardrails

1. **Keep schedule body `{}`** so the default `limit = 25` stays in effect; never hardcode a higher limit in the cron.  
2. **For single-user tests**, leave the schedule alone and instead run manual POSTs with the documented curl snippet (README).  
3. **Always run with `"dryRun": true` first**, review the summary, then rerun with `dryRun: false` once confirmed.  
4. **Pin the curl + dry-run instructions** in the ops/runbook so every operator follows the same process.

### When to Fix

Documented guardrails are acceptable for now, but we should revisit once we have:
- Automated alerting tied to the schedule.  
- Safer batching (e.g., per-user job queue).  
- UI tooling that enforces dry-run-before-live.

---

## Test / Dry-Run Procedure (Reconciliation Flow)

Repeat this flow whenever you need to verify `weekly-close` + `settlement-reconcile` end-to-end. It assumes Stripe test keys and the seeded users from `rpc_setup_test_data`.

1. **Seed fixtures**  
   ```sql
   select public.rpc_setup_test_data();
   ```
   This creates Test User 1 (`1111…`) with a real Stripe test customer and week-long usage.

2. **Run weekly-close**  
   ```bash
   PROJECT_REF=...; SERVICE_ROLE_KEY=...
   curl -X POST \
     "https://${PROJECT_REF}.functions.supabase.co/weekly-close" \
     -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
     -H "Content-Type: application/json"
   ```
   Expect `chargedUsers: 1` (Test User 1) and note the returned PaymentIntent ID.

3. **Simulate late sync using `test_rpc_sync_daily_usage.sql`**  
   Run the script in Supabase SQL Editor. It now:
   - Sets session JWT claims for Test User 1.
   - Posts representative usage via `rpc_sync_daily_usage`.
   - Runs the “Late sync” block which:
     - Retrieves the latest PaymentIntent for that week from `public.payments`.
     - Sets `charged_amount_cents = 150`, `actual_amount_cents = 0`.
     - Flags `reconciliation_delta_cents = -150`, `needs_reconciliation = true`.

   You should see:
   ```json
   {"week_start_date":"YYYY-MM-DD","charged_amount_cents":150,"actual_amount_cents":0,"reconciliation_delta_cents":-150,"needs_reconciliation":true}
   ```

4. **Run `quick-handler` (settlement-reconcile)**  
   - Dry run:
     ```bash
     curl -X POST \
       "https://${PROJECT_REF}.functions.supabase.co/quick-handler" \
       -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
       -H "Content-Type: application/json" \
       -d '{"week":"YYYY-MM-DD","dryRun":true}'
     ```
   - Live run (same payload, `dryRun:false`). Success looks like:
     ```json
     {
       "processed": 1,
       "refundsIssued": 1,
       "details": [{"userId":"1111…","action":"refund","amountCents":150}]
     }
     ```

5. **Verify tables & Stripe**
   ```sql
   select charged_amount_cents,
          actual_amount_cents,
          refund_amount_cents,
          settlement_status,
          needs_reconciliation
   from public.user_week_penalties
   where user_id = '1111…'
     and week_start_date = 'YYYY-MM-DD';

   select payment_type, amount_cents, status
   from public.payments
   where week_start_date = 'YYYY-MM-DD'
     and user_id = '1111…'
   order by created_at desc;
   ```
   Expect `needs_reconciliation = false`, `refund_amount_cents = 150`, and a new `penalty_refund` row. Confirm the refund in Stripe.

6. **Reset (optional)**
   Re-run `rpc_setup_test_data` to wipe the week, or manually clear the rows if running multiple iterations.

### Notes
- The SQL script **will refuse** to set `needs_reconciliation` if it cannot find a real PaymentIntent; fix the charge step first.
- Always keep the schedule cron body `{}` so production still caps at `limit = 25`.
- Document the PaymentIntent ID from `weekly-close` in your QA notes for auditability.

---

## Security: service_role key embedded in `call_weekly_close`

**Status**: Known Issue – Security Hygiene  
**Severity**: High (Secrets Exposure)  
**Date Identified**: 2025-12-10  

### Description
The live `call_weekly_close` function body includes the Supabase `service_role` key in plain text (Authorization header). This key is highly privileged and should never be stored inside SQL or committed to the repo.

### Impact / Risk
- Anyone with access to function definitions or dumps could copy the key and use it for privileged operations.
- The key was present in the schema dump; backups or git history may capture it.

### Mitigation / Remediation
1) **Rotate** the service_role key in Supabase (Settings → API).  
2) **Move the key to a DB setting**, e.g. `ALTER DATABASE postgres SET app.settings.service_role_key = 'NEW_KEY';` (run once, do not commit).  
3) **Update the function** to use the setting-based header:  
   ```sql
   'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
   ```  
4) **Re-dump** the schema after the fix to ensure no plain-text key remains in repo/backups.  

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

## Phase 1: App Startup Loading Screen Delay

**Status**: Known Issue - UX/Performance  
**Severity**: Low (User Experience)  
**Date Identified**: 2025-12-25  
**Phase**: Phase 1 - App Launch

### Description

When starting the app, there is a prolonged white/loading screen that appears before the logo or any UI elements are shown. This creates a poor first impression and makes the app feel slow to launch.

### Symptoms

- White/blank screen visible for several seconds on app launch
- Logo or initial UI elements take too long to appear
- Users may think the app is frozen or not responding
- Occurs before any content is displayed

### Impact

**User Experience**: ⚠️ Medium - Poor first impression, feels unresponsive  
**Functional**: ✅ None - App eventually loads correctly  
**Performance**: ⚠️ Low - Perceived slowness even if actual load time is acceptable

### Proposed Fix

1. Investigate app initialization sequence - identify what's blocking UI rendering
2. Show splash screen or logo immediately on app launch
3. Optimize initial data loading (move non-critical operations to background)
4. Consider showing a loading indicator or branded splash screen during initialization
5. Profile app startup time to identify bottlenecks

### Code Locations

- `payattentionclub_app_1_1App.swift` (app initialization)
- `RootRouterView.swift` (initial screen routing)
- `AppModel.swift` (initial data loading)
- `LoadingView.swift` (loading screen implementation)

### Testing

1. Measure time from app launch to first UI element appearing
2. Test on different device models to identify device-specific delays
3. Profile with Instruments to find startup bottlenecks
4. Verify splash screen appears immediately if implemented

---

## Phase 1: FamilyActivityPicker Permission Screen Delay

**Status**: Known Issue - UX/Performance  
**Severity**: Low (User Experience)  
**Date Identified**: 2025-12-25  
**Phase**: Phase 1 - App Selection & Permissions

### Description

When pressing the "Select Apps" button for the first time (to grant FamilyControls permission), there is a 2-3 second delay before the system permission screen appears. This delay makes the app feel unresponsive and may cause users to tap the button multiple times.

### Symptoms

- 2-3 second delay between button tap and permission screen appearing
- No immediate feedback when button is pressed
- Users may think the button didn't work and tap again
- Only occurs on first-time permission request

### Impact

**User Experience**: ⚠️ Medium - Feels unresponsive, may cause confusion  
**Functional**: ✅ None - Permission screen eventually appears  
**Performance**: ⚠️ Low - System-level delay, not app code issue

### Root Cause

This is likely a system-level delay when iOS first presents the FamilyControls authorization screen. The system may need to:
- Initialize the FamilyControls framework
- Load the app selection UI
- Prepare system-level permission dialogs

### Proposed Fix

1. Add immediate visual feedback when button is pressed (loading indicator, button state change)
2. Show a brief message explaining that the permission screen will appear shortly
3. Disable button during the delay to prevent multiple taps
4. Consider showing a small loading spinner or "Preparing..." message
5. Investigate if there's a way to pre-warm the FamilyControls framework

### Code Locations

- `SetupView.swift` (app selection button)
- `AuthorizationView.swift` (if used for permissions)
- Any view that triggers `AuthorizationCenter.shared.requestAuthorization()`

### Testing

1. Measure time from button tap to permission screen appearance
2. Test on different iOS versions to see if delay varies
3. Verify button provides immediate feedback
4. Test with and without existing authorization to compare behavior

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

