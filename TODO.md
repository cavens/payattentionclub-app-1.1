# TODO & Known Issues

This document consolidates all known issues, bugs, and remaining tasks for V1.0 finalization.

---

## Known Issues & Bugs

This section tracks known bugs and issues that are not critical enough to block development but should be addressed in the future.

### Phase 3: Multiple Concurrent Syncs Issue

**Status**: Known Issue - Non-Critical  
**Severity**: Medium (Performance/Cost)  
**Date Identified**: 2025-11-28  
**Phase**: Phase 3 - Sync Manager Implementation

#### Description

Multiple concurrent calls to `syncDailyUsage()` are executing simultaneously instead of being serialized. When `syncToBackend()` is called multiple times (e.g., from app launch, foreground, and multiple views), 3-5 sync operations run concurrently, all syncing the same data.

#### Symptoms

- Multiple sync operations complete for the same entries
- All syncs share the same call ID (suspicious - should be unique UUIDs)
- Logs show multiple "✅ Successfully synced" messages for the same data
- Both `UsageSyncManager` coordinator and `BackendClient` guards are not preventing concurrent execution

#### Impact

**Functional**: ✅ None - Syncs complete successfully, data reaches backend, entries marked as synced  
**Performance**: ⚠️ Medium - 3-5x more network requests and database writes than necessary  
**Cost**: ⚠️ Medium - More Supabase RPC calls = higher costs at scale  
**User Experience**: ✅ None - Happens in background, users don't notice  
**Data Integrity**: ✅ None - Backend appears idempotent, no data corruption observed

#### Root Cause Analysis

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

#### Code Locations

- `UsageSyncManager.swift`: `syncToBackend()` method, `SyncCoordinator` class
- `BackendClient.swift`: `syncDailyUsage()` method, static `_isSyncingDailyUsage` flag and `_syncQueue`

#### When to Fix

**Priority**: Medium  
**Suggested Timeline**: After Phase 4+ implementation, or when:
- Costs become an issue
- Performance degrades noticeably
- Data inconsistencies appear
- Dedicated optimization time available

#### Proposed Fix

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

#### Testing

To verify fix:
1. Trigger multiple sync calls simultaneously (app launch + foreground + manual)
2. Check logs for:
   - Only ONE sync operation completing
   - Other calls being rejected or queued
   - Unique call IDs for each attempt
3. Verify backend receives only one sync request per entry

---

### Phase 4C: Reconciliation Guardrails Depend on Operator Discipline

**Status**: Known Issue – Operational Risk  
**Severity**: Medium (Financial/Support)  
**Date Identified**: 2025-12-07  
**Phase**: Phase 4C – Integration & Guardrails

#### Description

The `settlement-reconcile` scheduler can be misconfigured (e.g., larger payloads, no dry run) which increases the blast radius if Stripe refunds/charges have bugs. The safe-ops steps live in `supabase/functions/settlement-reconcile/README.md`, but they are easy to skip when someone new touches the cron or runs it manually.

#### Symptoms / Risks

- Cron body is edited to include a high `limit`, so one run can touch hundreds of rows.
- Operators trigger the Edge Function manually without doing a dry run first.
- Team members do not have the curl snippet handy and improvise calls, risking malformed payloads.

#### Impact

**Financial**: ⚠️ Medium – unintended bulk refunds/charges, Stripe disputes.  
**Support**: ⚠️ Medium – flood of user questions if reconciliation misfires.  
**Product**: ✅ None – feature works, risk comes from ops process.  
**Data Integrity**: ⚠️ Low – incorrect settlement rows until manual cleanup.

#### Mitigation / Guardrails

1. **Keep schedule body `{}`** so the default `limit = 25` stays in effect; never hardcode a higher limit in the cron.  
2. **For single-user tests**, leave the schedule alone and instead run manual POSTs with the documented curl snippet (README).  
3. **Always run with `"dryRun": true` first**, review the summary, then rerun with `dryRun: false` once confirmed.  
4. **Pin the curl + dry-run instructions** in the ops/runbook so every operator follows the same process.

#### When to Fix

Documented guardrails are acceptable for now, but we should revisit once we have:
- Automated alerting tied to the schedule.  
- Safer batching (e.g., per-user job queue).  
- UI tooling that enforces dry-run-before-live.

---

### DST Transition Issue in Grace Period Calculation

**Status**: Known Issue – Timing Bug  
**Severity**: High (Financial/Compliance)  
**Date Identified**: 2026-01-15  
**Phase**: Settlement Process

#### Description

The `getGraceDeadline()` function in `supabase/functions/_shared/timing.ts` uses `setUTCDate()` which adds 1 day in UTC, not accounting for Daylight Saving Time (DST) transitions. This causes the grace period to be incorrect (23 or 25 hours instead of 24 hours) when a week spans a DST transition.

**Problem**: If a commitment week spans a DST transition (spring forward in March or fall back in November), the grace period calculation will be off by 1 hour:
- **Spring forward**: Grace period = 23 hours (too short) - users charged too early
- **Fall back**: Grace period = 25 hours (too long) - users charged too late

#### Impact

**Financial**: ⚠️ High – Users could be charged incorrectly during DST transition weeks  
**Compliance**: ⚠️ High – Grace period not matching promised 24 hours  
**User Experience**: ⚠️ Medium – Confusion if charged at wrong time  
**Data Integrity**: ⚠️ Low – Settlement still works, just at wrong time

#### Root Cause

**File**: `supabase/functions/_shared/timing.ts:122-137`

```typescript
// ❌ Current code (WRONG):
const grace = new Date(weekEndDate);
grace.setUTCDate(grace.getUTCDate() + 1); // Adds 1 day in UTC, not ET
```

This adds exactly 24 hours in UTC, but we need exactly 24 hours in ET timezone. When DST changes, the offset between UTC and ET changes, causing the grace period to be incorrect.

#### When to Fix

**Priority**: High  
**Timeline**: Before production launch (affects users during DST transition weeks)  
**Affected Dates**: 
- Spring forward: Weeks ending March 8-15 (approximately)
- Fall back: Weeks ending November 1-8 (approximately)

#### Proposed Fix

See detailed fix proposal in: `docs/DST_FIX_PROPOSAL.md`

**Summary**: Replace `setUTCDate()` with timezone-aware calculation using Intl API:
1. Convert Monday 12:00 ET to date components
2. Add 1 day to date components (not time)
3. Set to 12:00 ET
4. Convert back to UTC Date, accounting for DST offset change

#### Testing

**Can test immediately** using mock dates (no need to wait for March/November):
- Spring forward test: March 8, 2026 (EST) → March 10, 2026 (EDT)
- Fall back test: November 1, 2026 (EDT) → November 3, 2026 (EST)
- Normal week test: January 12, 2026 (EST) → January 13, 2026 (EST)

Test file template provided in `docs/DST_FIX_PROPOSAL.md`.

**Related Documentation**:
- `docs/NORMAL_MODE_RISKS_ANALYSIS.md` - Full analysis of normal mode risks
- `docs/DST_FIX_PROPOSAL.md` - Detailed fix proposal and test cases

---

### Security: service_role key embedded in `call_weekly_close`

**Status**: Known Issue – Security Hygiene  
**Severity**: High (Secrets Exposure)  
**Date Identified**: 2025-12-10

#### Description
The live `call_weekly_close` function body includes the Supabase `service_role` key in plain text (Authorization header). This key is highly privileged and should never be stored inside SQL or committed to the repo.

#### Impact / Risk
- Anyone with access to function definitions or dumps could copy the key and use it for privileged operations.
- The key was present in the schema dump; backups or git history may capture it.

#### Mitigation / Remediation
1) **Rotate** the service_role key in Supabase (Settings → API).  
2) **Move the key to a DB setting**, e.g. `ALTER DATABASE postgres SET app.settings.service_role_key = 'NEW_KEY';` (run once, do not commit).  
3) **Update the function** to use the setting-based header:  
   ```sql
   'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
   ```  
4) **Re-dump** the schema after the fix to ensure no plain-text key remains in repo/backups.

---

### Phase 2: Weekly Grace Window Needs Pre-Week Buffer

**Status**: Known Issue - UX/Behavioral  
**Severity**: Low (User Expectation)  
**Date Identified**: 2025-12-01  
**Phase**: Phase 2 - Commitment Tracking

#### Description

Weekly commitments currently apply a **24-hour grace period only *after* the week ends**. We now need a **2–4 hour buffer *before* the week ends** during which usage should **not** be counted. This ensures users get an automatic "cool down" window leading into the week transition without impacting their streak.

#### Symptoms

- Usage recorded during the final hours of the week still affects the outgoing week totals.
- Users see last-minute usage reflected in the dashboard when it should be ignored.
- Grace logic does not match current product expectations (pre-week buffer missing).

#### Impact

**Functional**: ⚠️ Low - Tracking still works but doesn't follow desired grace rules  
**User Experience**: ⚠️ Medium - Users may feel penalized for last-minute usage  
**Data Integrity**: ✅ None - Data is accurate, just counted when it shouldn't be  
**Product Consistency**: ⚠️ Medium - Behavior differs from documented UX

#### Proposed Fix

1. Update commitment evaluation logic to treat **the final 2–4 hours of the week as grace time** (usage ignored).
2. Maintain the existing **24-hour post-week grace period**.
3. Ensure UI labels/tooltips reflect the expanded window.
4. Add automated tests covering both pre- and post-week grace windows.

#### Code Locations

- `UsageTracker.swift` (weekly window calculations)
- `CommitmentEvaluator.swift` or equivalent logic handling grace periods
- Any UI components reflecting "time remaining" for the week

#### Testing

1. Simulate time within final 2–4 hours of a weekly window: verify usage is ignored.
2. Verify usage outside the buffer still counts.
3. Confirm 24-hour post-week grace still works.

---

### Phase 1: App Startup Loading Screen Delay

**Status**: Known Issue - UX/Performance  
**Severity**: Low (User Experience)  
**Date Identified**: 2025-12-25  
**Phase**: Phase 1 - App Launch

#### Description

When starting the app, there is a prolonged white/loading screen that appears before the logo or any UI elements are shown. This creates a poor first impression and makes the app feel slow to launch.

#### Symptoms

- White/blank screen visible for several seconds on app launch
- Logo or initial UI elements take too long to appear
- Users may think the app is frozen or not responding
- Occurs before any content is displayed

#### Impact

**User Experience**: ⚠️ Medium - Poor first impression, feels unresponsive  
**Functional**: ✅ None - App eventually loads correctly  
**Performance**: ⚠️ Low - Perceived slowness even if actual load time is acceptable

#### Proposed Fix

1. Investigate app initialization sequence - identify what's blocking UI rendering
2. Show splash screen or logo immediately on app launch
3. Optimize initial data loading (move non-critical operations to background)
4. Consider showing a loading indicator or branded splash screen during initialization
5. Profile app startup time to identify bottlenecks

#### Code Locations

- `payattentionclub_app_1_1App.swift` (app initialization)
- `RootRouterView.swift` (initial screen routing)
- `AppModel.swift` (initial data loading)
- `LoadingView.swift` (loading screen implementation)

#### Testing

1. Measure time from app launch to first UI element appearing
2. Test on different device models to identify device-specific delays
3. Profile with Instruments to find startup bottlenecks
4. Verify splash screen appears immediately if implemented

---

### Phase 1: FamilyActivityPicker Permission Screen Delay

**Status**: Known Issue - UX/Performance  
**Severity**: Low (User Experience)  
**Date Identified**: 2025-12-25  
**Phase**: Phase 1 - App Selection & Permissions

#### Description

When pressing the "Select Apps" button for the first time (to grant FamilyControls permission), there is a 2-3 second delay before the system permission screen appears. This delay makes the app feel unresponsive and may cause users to tap the button multiple times.

#### Symptoms

- 2-3 second delay between button tap and permission screen appearing
- No immediate feedback when button is pressed
- Users may think the button didn't work and tap again
- Only occurs on first-time permission request

#### Impact

**User Experience**: ⚠️ Medium - Feels unresponsive, may cause confusion  
**Functional**: ✅ None - Permission screen eventually appears  
**Performance**: ⚠️ Low - System-level delay, not app code issue

#### Root Cause

This is likely a system-level delay when iOS first presents the FamilyControls authorization screen. The system may need to:
- Initialize the FamilyControls framework
- Load the app selection UI
- Prepare system-level permission dialogs

#### Proposed Fix

1. Add immediate visual feedback when button is pressed (loading indicator, button state change)
2. Show a brief message explaining that the permission screen will appear shortly
3. Disable button during the delay to prevent multiple taps
4. Consider showing a small loading spinner or "Preparing..." message
5. Investigate if there's a way to pre-warm the FamilyControls framework

#### Code Locations

- `SetupView.swift` (app selection button)
- `AuthorizationView.swift` (if used for permissions)
- Any view that triggers `AuthorizationCenter.shared.requestAuthorization()`

#### Testing

1. Measure time from button tap to permission screen appearance
2. Test on different iOS versions to see if delay varies
3. Verify button provides immediate feedback
4. Test with and without existing authorization to compare behavior

---

### Phase 1: Email Contact Limitation with Sign in with Apple

**Status**: Known Issue - Potential Product Limitation  
**Severity**: Low (Growth & Support)  
**Date Identified**: 2025-12-01  
**Phase**: Phase 1 - Authentication & Onboarding  
**Priority**: Low

#### Description

Users signing in exclusively via "Sign in with Apple" provide randomized, pseudonymous relay email addresses (e.g., `abcd1234@privaterelay.appleid.com`). We currently **do not collect a real contact email**, so:
- Transactional emails (weekly summaries, nudges) may be filtered or ignored.
- We can't guarantee we can reach users outside the app.
- Support follow-ups are difficult when Apple relay is disabled or rate-limited.

#### Symptoms

- Email campaigns (Loops) only reach Apple relay addresses.
- Some users report never receiving reminders.
- We cannot correlate app accounts with real customer support tickets.

#### Impact

**Product**: ⚠️ Medium – reduces engagement with email reminders and nudges.  
**Support**: ⚠️ Medium – harder to reach customers proactively.  
**Compliance**: ✅ None – still compliant, but Apple may throttle relays.  
**Data**: ✅ None – no data loss, just communication friction.

#### Proposed Fix

1. Prompt users (post-onboarding) to optionally share their real email address for reminders/support.  
2. Store it securely in Supabase and mark whether the user opted in.  
3. Update backend/email logic to prefer the real email when available, fallback to Apple relay otherwise.  
4. Add UI copy explaining why the primary email improves reminders.  
5. **For later**: Provide a mandatory email input field if users did not provide their real email address using Apple Sign-In. This ensures we always have a way to contact users for important communications (charges, refunds, account issues, etc.).

#### Code/Feature Touchpoints

- `AuthorizationView.swift` (post-login UI)  
- `BackendClient` / Supabase schema (extra user field for contact email + consent flag)  
- Reminder scheduling logic (Loops template data)  
- Account settings view (allow editing/removal)  
- New: Email input form for users who didn't share email via Apple Sign-In

#### Testing

- Sign in via Apple, add a real email, verify Supabase stores and Loops sends to the correct address.  
- Ensure opt-out/respect user deletion of the real email.  
- Confirm backend falls back to Apple relay if no real email exists.  
- Test mandatory email collection flow for users with private relay emails.

---

### Screen Time Revocation Handling

**Status**: Known Issue - Behavioral  
**Severity**: Medium (User Experience)  
**Date Identified**: 2025-12-27  
**Phase**: V1.0 Finalization

#### Description

Document behavior when FamilyControls permission is revoked mid-week. Need to add mitigations/alerts to handle this scenario gracefully.

#### Impact

**User Experience**: ⚠️ Medium - Users may lose tracking if permission is revoked  
**Functional**: ⚠️ Medium - App may not handle revocation gracefully  
**Data Integrity**: ⚠️ Low - May lose usage data if not handled properly

#### Proposed Fix

1. Document expected behavior when permission is revoked
2. Add UI alerts/notifications when revocation is detected
3. Implement graceful degradation (show message, allow re-authorization)
4. Ensure no data loss occurs during revocation

---

## Test / Dry-Run Procedure (Reconciliation Flow)

Repeat this flow whenever you need to verify `weekly-close` + `settlement-reconcile` end-to-end. It assumes Stripe test keys and the seeded users from `rpc_setup_test_data`.

1. **Seed fixtures**  
   ```sql
   select public.rpc_setup_test_data();
   ```
   This creates Test User 1 (`1111…`) with a real Stripe test customer and week-long usage.

2. **Run weekly-close**  
   ```bash
   PROJECT_REF=...; SERVICE_ROLE_KEY=...
   curl -X POST \
     "https://${PROJECT_REF}.functions.supabase.co/weekly-close" \
     -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
     -H "Content-Type: application/json"
   ```
   Expect `chargedUsers: 1` (Test User 1) and note the returned PaymentIntent ID.

3. **Simulate late sync using `test_rpc_sync_daily_usage.sql`**  
   Run the script in Supabase SQL Editor. It now:
   - Sets session JWT claims for Test User 1.
   - Posts representative usage via `rpc_sync_daily_usage`.
   - Runs the "Late sync" block which:
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

## Other Tasks & Readiness Items

This section contains todos and readiness items that are not bugs or issues, but need to be completed for V1.0 finalization.

### 1. Testing Rig

Build a simple seed → cron → verify harness so weekly settlement scenarios can be tested with minimal manual steps.

**Priority**: Medium  
**Timeline**: Before TestFlight submission

---

### 2. Known Issues Audit

Revisit `KNOWN_ISSUES.md`, confirm statuses, and close/flag anything outdated.

**Priority**: Low  
**Timeline**: Ongoing

---

### 3. UI Polish

Final pass on Authorization/Monitor/Bulletin screens:
- Countdown banner styling
- Settlement card styling
- Remove temporary buttons
- Ensure consistent visual design

**Priority**: Medium  
**Timeline**: Before TestFlight submission

---

### 4. Environment Separation

Ensure distinct staging + production Supabase projects:
- Staging → Stripe test mode
- Production → Stripe live mode
- Verify environment variables are correctly configured
- Add safeguards to prevent mixing environments

**Priority**: High  
**Timeline**: Before production deployment

---

### 5. TestFlight Readiness

- Finish Apple entitlement approvals
- Prepare provisioning profiles
- Submit build to TestFlight
- Set up TestFlight groups and testing instructions

**Priority**: High  
**Timeline**: Before public release

---

### 6. Monitoring & Alerts

- Structured logging for reminder/settlement/reconcile functions
- Add alert hooks (Slack/email) for failures or missed schedules
- Set up monitoring dashboards
- Configure error tracking

**Priority**: Medium  
**Timeline**: Before production deployment

---

### 7. Automated Data Cleanup

Scripts to reset seeded commitments/penalties and Stripe test charges after QA runs.

**Priority**: Low  
**Timeline**: Ongoing (as needed)

---

### 8. Config Sanity Check

Tooling to verify Supabase/Stripe env vars (URL, keys, cron schedule) before deploy:
- Pre-deployment validation script
- Environment variable verification
- Cron schedule validation

**Priority**: Medium  
**Timeline**: Before production deployment

---

### 9. App Group Heartbeat

Diagnostic screen/log to confirm DeviceActivity monitor is writing usage data:
- Add diagnostic view in app
- Show last sync timestamp
- Display app group data status
- Help debug monitoring issues

**Priority**: Low  
**Timeline**: Before TestFlight (for debugging)

---

### 10. Documentation Refresh

Update README/architecture/testing docs with:
- Tuesday-noon settlement cadence
- QA process documentation
- Updated setup instructions
- Deployment workflows

**Priority**: Medium  
**Timeline**: Before production deployment

---

### 11. Security Review

Audit auth scopes, secret storage, and request logging to ensure no sensitive data leaks:
- Review all API calls for sensitive data
- Verify secret storage practices
- Check logging for PII exposure
- Review access controls

**Priority**: High  
**Timeline**: Before production deployment

---

### 12. Code Cleanup

- Remove stray debug logs
- Remove "slur" comments
- Tidy unused files
- Enforce code formatting
- Remove temporary test code

**Priority**: Low  
**Timeline**: Ongoing

---

### 13. Stripe Mapping Clarity

Explicit mapping of staging ↔ Stripe sandbox, production ↔ Stripe live, with deployment safeguards:
- Document environment mappings
- Add deployment checks
- Prevent accidental cross-environment usage
- Add validation scripts

**Priority**: High  
**Timeline**: Before production deployment

---

### 14. Settlement Process Verification

Triple-check the entire settlement process to ensure everything works correctly:
- Verify authorization amount cap is enforced (actual penalty never exceeds authorization)
- Test settlement flow with various scenarios:
  - User syncs before Tuesday noon → charge actual (capped at authorization)
  - User doesn't sync → charge authorization at Tuesday noon
  - User syncs late → reconciliation uses capped actual
  - User exceeds authorization cap → verify charge is capped correctly
- Verify reconciliation logic uses capped actual (not raw actual)
- Test edge cases (zero penalty, full authorization, partial usage, etc.)
- Verify all settlement-related functions are working:
  - `run-weekly-settlement.ts` (bright-service)
  - `rpc_sync_daily_usage.sql`
  - `quick-handler` (settlement-reconcile)
- Check that tests cover all scenarios

**Priority**: High  
**Timeline**: Before production launch  
**Status**: After recent authorization cap bug fix

---

### 15. MonitorView Authorization Amount Display Fix

**Status**: TODO  
**Severity**: Medium (Data Accuracy)  
**Date Identified**: 2025-12-29  
**Phase**: V1.0 Finalization

#### Description

In the MonitorView, the small text underneath that says "with a maximum of xxx" currently displays `model.authorizationAmount`, which is the current authorization amount at this moment. However, it should display the authorization amount that was stored as part of the commitment when it was created (the `max_charge_cents` from the commitment record).

#### Impact

**Data Accuracy**: ⚠️ Medium - Users see the current authorization amount instead of the commitment's original authorization amount  
**User Experience**: ⚠️ Medium - May cause confusion if authorization amount changes  
**Functional**: ✅ None - App works, but displays incorrect value

#### Proposed Fix

1. Fetch the commitment's `max_charge_cents` from the backend (stored in `commitments` table)
2. Use `weekStatus.userMaxChargeCents` if available (from `rpc_get_week_status`)
3. Fallback to `model.authorizationAmount` only if commitment data is not available
4. Ensure the displayed value matches what was actually authorized at commitment creation time

#### Code Locations

- `MonitorView.swift` - Text displaying "with a maximum of \(model.authorizationAmount)"
- `AppModel.swift` - May need to store commitment's original authorization amount
- `BackendClient.swift` - `WeekStatusResponse` already includes `userMaxChargeCents` from commitment

#### Testing

1. Create a commitment and note the authorization amount
2. Verify MonitorView displays the commitment's original authorization amount
3. Test with and without `weekStatus` data available
4. Verify fallback behavior works correctly

**Priority**: Medium  
**Timeline**: Before production launch

---

### 16. Weekly Notification System

**Status**: TODO  
**Severity**: Medium (User Engagement)  
**Date Identified**: 2025-12-29  
**Phase**: V1.0 Finalization

#### Description

Implement a notification system that sends push notifications to users at different points during their commitment week to keep them informed about their usage and approaching deadlines.

#### Notification Triggers

1. **Approaching Limit Warning**
   - Trigger: When user reaches ~80-90% of their weekly limit
   - Purpose: Give users advance warning before hitting their limit
   - Message: "You're approaching your weekly limit. X minutes remaining."

2. **Limit Reached**
   - Trigger: When user hits their exact weekly limit
   - Purpose: Alert users that they've reached their limit and penalties will start
   - Message: "You've reached your weekly limit. Penalties will apply for additional usage."

3. **Penalty Milestones**
   - Trigger: Every $10 (or equivalent in penalty) that user exceeds their limit
   - Purpose: Keep users informed of accumulating penalties
   - Message: "You've exceeded your limit by $X. Current penalty: $Y."

4. **Deadline Reminder**
   - Trigger: At the deadline (Monday/Tuesday 12:00 PM Eastern Time)
   - Purpose: Remind users that the week is ending and settlement will occur
   - Message: "Your commitment week ends today at noon ET. Final penalty: $X."

#### Technical Requirements

- Implement local notification scheduling in iOS app
- Calculate notification timing based on:
  - Current usage vs. limit (for approaching/hit limit notifications)
  - Current penalty amount (for $10 milestone notifications)
  - Week deadline timestamp (for deadline notification)
- Handle edge cases:
  - User exceeds limit before notification can be sent
  - Multiple notifications scheduled for same time
  - User revokes notification permissions
  - App is closed when notification should trigger
- Ensure notifications are accurate and don't spam users

#### Impact

**User Engagement**: ⚠️ Medium - Keeps users informed and engaged with their commitment  
**User Experience**: ⚠️ Medium - Helps users stay aware of their usage and penalties  
**Functional**: ✅ None - App works without notifications, but engagement may suffer  
**Product**: ⚠️ Medium - Important for user retention and commitment adherence

#### Proposed Implementation

1. **Notification Manager**
   - Create `NotificationManager` class to handle scheduling and cancellation
   - Integrate with `UsageTracker` to monitor usage changes
   - Schedule notifications based on current usage and limit

2. **Usage Monitoring**
   - Monitor `currentUsageSeconds` vs `limitMinutes` to detect approaching/hit limit
   - Monitor `currentPenalty` to detect $10 milestones
   - Update scheduled notifications as usage changes

3. **Deadline Scheduling**
   - Schedule deadline notification when commitment is created
   - Use `getNextMondayNoonEST()` to calculate exact deadline time
   - Handle timezone conversion (Eastern Time)

4. **Notification Content**
   - Create notification templates for each trigger type
   - Include relevant data (minutes remaining, penalty amount, etc.)
   - Ensure messages are clear and actionable

5. **Permission Handling**
   - Request notification permissions during onboarding
   - Handle permission denial gracefully
   - Provide settings option to enable/disable notifications

#### Code Locations

- New file: `NotificationManager.swift` (notification scheduling and management)
- `AppModel.swift` - Integrate notification scheduling with usage updates
- `UsageTracker.swift` - Monitor usage changes to trigger notifications
- `AuthorizationView.swift` - Request notification permissions
- `SetupView.swift` - Request notification permissions during onboarding
- Settings view (if exists) - Allow users to manage notification preferences

#### Testing

1. Test approaching limit notification (schedule when at 80% of limit)
2. Test limit reached notification (trigger when limit is hit)
3. Test $10 milestone notifications (verify they trigger at correct intervals)
4. Test deadline notification (schedule for correct time, verify timezone handling)
5. Test notification cancellation when commitment ends
6. Test permission handling (granted, denied, not determined)
7. Test notifications when app is closed/backgrounded
8. Verify notifications don't spam (e.g., multiple $10 notifications in quick succession)

**Priority**: Medium  
**Timeline**: Before production launch (can be added post-launch if needed)

---

### 17. Startup Load Time Investigation

**Status**: TODO  
**Severity**: High (User Experience)  
**Date Identified**: 2025-12-29  
**Phase**: V1.0 Finalization

#### Description

Investigate and optimize app startup load time. Currently experiencing long white screen delays (13+ seconds) and performance issues during initial launch, especially on first install.

#### Issues to Investigate

- Measure actual startup time from app launch to first UI element
- Profile with Instruments to identify bottlenecks
- Check if debugger/Xcode connection is affecting performance
- Verify UserDefaults reads are truly removed from startup path
- Check for any remaining blocking operations during initialization
- Test on physical device vs simulator
- Test with and without Xcode debugger attached
- Compare first install vs subsequent launches

#### Impact

**User Experience**: ⚠️ High - Poor first impression, feels unresponsive  
**Performance**: ⚠️ High - Long delays make app feel broken  
**Functional**: ✅ None - App eventually loads correctly

#### Proposed Investigation Steps

1. Profile app startup with Instruments (Time Profiler)
2. Measure time from app launch to LoadingView appearance
3. Measure time from LoadingView to SetupView appearance
4. Test on physical device without Xcode debugger
5. Check for any remaining UserDefaults reads in startup path
6. Verify all heavy operations are truly deferred
7. Check if SwiftUI view hierarchy is causing delays
8. Test on different device models (older vs newer)

#### Code Locations

- `payattentionclub_app_1_1App.swift` (app initialization)
- `AppModel.swift` (finishInitialization)
- `LoadingView.swift` (loading screen)
- `RootRouterView.swift` (navigation)

**Priority**: High  
**Timeline**: Before production launch

---

### 18. Authorization Amount Calculation Verification

**Status**: TODO  
**Severity**: Medium (Data Accuracy)  
**Date Identified**: 2025-12-29  
**Phase**: V1.0 Finalization

#### Description

Double-check the authorization amount calculation on the backend. The calculation logic may be incorrect or producing unexpected values.

#### Issues to Verify

- Verify `rpc_preview_max_charge` calculation logic
- Verify `rpc_create_commitment` uses same calculation
- Check that authorization amount matches expected values for different scenarios:
  - Different time limits (30 min to 42 hours)
  - Different penalty rates ($0.01 to $5.00)
  - Different app counts
  - Different deadline dates
- Verify calculation accounts for all factors correctly:
  - Minutes remaining until deadline
  - Limit minutes
  - Penalty per minute
  - App count (risk factor)
  - Potential overage calculation
- Compare frontend preview calculation with backend calculation
- Test edge cases (minimum values, maximum values, boundary conditions)

#### Impact

**Data Accuracy**: ⚠️ Medium - Incorrect authorization amounts could affect user charges  
**Financial**: ⚠️ Medium - Wrong calculations could lead to incorrect charges or caps  
**User Experience**: ⚠️ Medium - Users may see unexpected authorization amounts

#### Proposed Verification Steps

1. Review `rpc_preview_max_charge` SQL function logic
2. Review `rpc_create_commitment` SQL function logic
3. Compare calculation formulas between preview and create
4. Test with various input combinations
5. Verify edge cases (minimum/maximum values)
6. Check that risk factor calculation is correct
7. Verify potential overage calculation is accurate
8. Test with real user scenarios

#### Code Locations

- `supabase/sql-drafts/rpc_preview_max_charge.sql` (or equivalent)
- `supabase/sql-drafts/rpc_create_commitment.sql` (or equivalent)
- `BackendClient.swift` - `previewMaxCharge()` method
- `AppModel.swift` - `fetchAuthorizationAmount()` method
- `AuthorizationView.swift` - Authorization amount display

#### Testing

1. Test authorization calculation with various time limits
2. Test with different penalty rates
3. Test with different app counts
4. Test with different deadline dates
5. Compare preview vs actual commitment amounts
6. Verify calculations match expected formulas
7. Test edge cases and boundary conditions

**Priority**: Medium  
**Timeline**: Before production launch

---

### 19. Backend Backward Compatibility Enforcement

**Status**: TODO  
**Severity**: High (API Stability)  
**Date Identified**: 2025-12-29  
**Phase**: V1.0 Finalization

#### Description

Currently, the deployment script (`scripts/deploy.sh`) does not check for backward compatibility when deploying backend changes. We have a policy to maintain "one version backend compatible" at all times, but there are no automated checks to enforce this policy.

#### Current State

The deployment script performs:
- ✅ Secrets check
- ✅ Test suite execution
- ✅ Git operations (stage, commit, push)
- ✅ RPC function deployment
- ✅ Edge function deployment

**Missing:**
- ❌ No version tracking
- ❌ No compatibility validation
- ❌ No breaking change detection
- ❌ No validation against previous client versions

#### Impact

**API Stability**: ⚠️ High - Breaking changes could break existing client apps  
**User Experience**: ⚠️ High - Users on older app versions could experience failures  
**Data Integrity**: ⚠️ Medium - Incompatible changes could cause data corruption  
**Deployment Risk**: ⚠️ High - No safety net to prevent breaking changes

#### Required Implementation

1. **Version Tracking System**
   - Track backend API version in database/config
   - Track client app versions currently in use
   - Maintain version history
   - Document version compatibility matrix

2. **Compatibility Validation Checks**
   - Validate RPC function signatures haven't changed in breaking ways:
     - Parameter additions/removals
     - Parameter type changes
     - Return type changes
     - Response format changes
   - Validate Edge function APIs haven't changed:
     - Request/response format changes
     - Required parameter additions
     - Endpoint removals
   - Check database migrations are backward compatible:
     - Column additions (OK) vs removals (breaking)
     - Type changes (breaking)
     - Constraint changes (potentially breaking)

3. **Deployment Gates**
   - Prevent deployment if breaking changes detected
   - Require explicit override for breaking changes
   - Test against previous client version before deployment
   - Compare new RPC functions with previous versions
   - Validate Edge function APIs match previous version

4. **Automated Testing**
   - Test new backend against previous client version
   - Validate response formats match previous version
   - Check that all existing RPC calls still work
   - Verify Edge function endpoints are still accessible

5. **Documentation**
   - Define what "one version back" means
   - Document breaking vs non-breaking changes
   - Create compatibility matrix
   - Document migration path for breaking changes

#### Proposed Implementation Steps

1. **Add Version Tracking**
   - Create version table or config entry
   - Track API version in code
   - Track client versions in use (from app analytics or database)

2. **Create Compatibility Check Script**
   - Script to compare RPC function signatures
   - Script to compare Edge function APIs
   - Script to validate database migrations
   - Integrate into deployment script

3. **Add Deployment Validation**
   - Pre-deployment checks for breaking changes
   - Require explicit approval for breaking changes
   - Test against previous client version

4. **Update Deployment Script**
   - Add compatibility check step before deployment
   - Fail deployment if breaking changes detected (unless overridden)
   - Log compatibility status

5. **Create Compatibility Matrix**
   - Document which backend versions work with which client versions
   - Maintain compatibility history
   - Update with each deployment

#### Code Locations

- `scripts/deploy.sh` - Add compatibility check step
- New: `scripts/check_backward_compatibility.sh` - Compatibility validation script
- New: `scripts/validate_rpc_signatures.sh` - RPC signature comparison
- New: `scripts/validate_edge_apis.sh` - Edge function API validation
- Database: Version tracking table or config
- Documentation: Compatibility matrix document

#### Testing

1. Test deployment with non-breaking changes (should pass)
2. Test deployment with breaking changes (should fail or require override)
3. Test compatibility check script with various scenarios
4. Verify previous client version still works after deployment
5. Test override mechanism for intentional breaking changes

#### Examples of Breaking vs Non-Breaking Changes

**Breaking Changes (Require Override):**
- Removing RPC function parameter
- Changing parameter type
- Changing return type structure
- Removing Edge function endpoint
- Adding required parameter to RPC function
- Removing database column
- Changing column type

**Non-Breaking Changes (Should Pass):**
- Adding optional RPC function parameter
- Adding new RPC function
- Adding new Edge function endpoint
- Adding database column
- Adding optional fields to response
- Performance improvements

**Priority**: High  
**Timeline**: Before production launch (critical for API stability)

---

### 20. Production Environment Setup (Migration: weekly-close → bright-service)

**Status**: TODO  
**Severity**: High (Production Readiness)  
**Date Identified**: 2026-01-11  
**Phase**: Migration: weekly-close → bright-service

#### Description

Production environment needs to be updated to match staging configuration for the migration from `weekly-close` to `bright-service`. Currently, staging is fully configured, but production still needs the same updates applied.

#### Required Steps

1. **Apply Migration to Production Database**
   - Run the migration SQL: `supabase/migrations/20260111170000_update_call_weekly_close_environment_aware_PRODUCTION.sql`
   - Or apply the function update manually via Supabase Dashboard → Production → SQL Editor
   - This updates `call_weekly_close()` to be environment-aware and call `bright-service`

2. **Configure Production app.settings**
   - Set `app.settings.service_role_key` = production secret key
   - Set `app.settings.supabase_url` = `https://whdftvcrtrsnefhprebj.supabase.co`
   - Can be done via SQL in the migration script, or manually in Supabase Dashboard → Database → Settings → Custom Postgres Config

3. **Set Up Production Cron Job**
   - Create `weekly-close-production` cron job
   - Schedule: Every Monday at 17:00 UTC (12:00 PM EST)
   - Command: `SELECT public.call_weekly_close();`
   - This is included in the migration SQL script

4. **Verify Production Deployment**
   - Edge Functions are already deployed: `bright-service` and `admin-close-week-now`
   - Verify `call_weekly_close()` function works correctly
   - Verify cron job is active and scheduled correctly
   - Test manual trigger to ensure it calls production's `bright-service`

#### Current Status

**Staging**: ✅ Complete
- Function updated and environment-aware
- Settings configured
- Cron job active

**Production**: ⚠️ Pending
- Edge Functions: ✅ Deployed
- Database function: ⚠️ Needs migration SQL applied
- Settings: ⚠️ Needs configuration
- Cron job: ⚠️ Needs creation

#### Impact

**Production Readiness**: ⚠️ High - Production will continue using old `weekly-close` until migration is complete  
**Functionality**: ⚠️ Medium - Production missing new features (revoked monitoring estimation, weekly_pools closing)  
**Consistency**: ⚠️ Medium - Staging and production will have different behavior until migration is complete

#### Files/Resources

- Migration SQL: `supabase/migrations/20260111170000_update_call_weekly_close_environment_aware_PRODUCTION.sql`
- Setup script: `scripts/setup_cron_jobs.sh production` (alternative to manual SQL)
- Production project ref: `whdftvcrtrsnefhprebj`
- Production URL: `https://whdftvcrtrsnefhprebj.supabase.co`

#### Testing

After applying changes to production:
1. Verify `call_weekly_close()` function exists and is updated
2. Verify `app.settings.service_role_key` is set (check via SQL: `SELECT current_setting('app.settings.service_role_key', true);`)
3. Verify `app.settings.supabase_url` is set (check via SQL: `SELECT current_setting('app.settings.supabase_url', true);`)
4. Verify cron job exists: `SELECT * FROM cron.job WHERE jobname = 'weekly-close-production';`
5. Manually test: `SELECT public.call_weekly_close();` (should call production's `bright-service`)
6. Check Edge Function logs to confirm `bright-service` was called

**Priority**: High  
**Timeline**: Before production deployment (should match staging configuration)

---

### 21. Production Reconciliation Cron Job Verification

**Status**: TODO  
**Severity**: High (Financial/Operational)  
**Date Identified**: 2026-01-11  
**Phase**: V1.0 Finalization

#### Description

Verify that the 10-minute reconciliation cron job in production is correctly configured and working. Specifically, ensure it is using the recent reconciliation queue implementation and processing reconciliation requests as expected.

#### Verification Steps

1. **Verify Cron Job Exists**
   - Check that the 10-minute reconciliation cron job exists in production
   - Confirm the cron job name and schedule (every 10 minutes)
   - Verify the cron job is active and enabled

2. **Verify Queue Implementation**
   - Confirm the cron job is using the recent reconciliation queue (not an old implementation)
   - Check that it's calling the correct Edge Function or RPC function
   - Verify it's processing items from the correct queue/table

3. **Test Functionality**
   - Manually trigger the cron job to verify it executes correctly
   - Check Edge Function logs to confirm it's being called
   - Verify it processes reconciliation items as expected
   - Test with sample data to ensure end-to-end flow works

4. **Compare with Staging**
   - Ensure production cron job configuration matches staging
   - Verify both environments use the same queue implementation
   - Confirm schedule and parameters are consistent

#### Impact

**Financial**: ⚠️ High - Reconciliation is critical for accurate charges/refunds  
**Operational**: ⚠️ High - Cron job must work correctly for settlement process  
**Data Integrity**: ⚠️ Medium - Incorrect reconciliation could affect user charges

#### Code/Configuration Locations

- Production Supabase Dashboard → Database → Cron Jobs
- Reconciliation Edge Function: `quick-handler` or `settlement-reconcile`
- Queue/table implementation (recent reconciliation queue)
- Cron job SQL definition

#### Testing

1. Query production cron jobs: `SELECT * FROM cron.job WHERE jobname LIKE '%reconcile%';`
2. Check cron job schedule and command
3. Manually trigger the cron job and verify execution
4. Check Edge Function logs for successful execution
5. Verify reconciliation items are processed correctly
6. Compare configuration with staging environment

**Priority**: High  
**Timeline**: Before production deployment (critical for settlement process)

---

### 22. Comprehensive Test Review After Backend Deadline Calculation Changes

**Status**: TODO  
**Severity**: High (Test Coverage)  
**Date Identified**: 2026-01-15  
**Phase**: V1.0 Finalization

#### Description

After implementing the backend deadline calculation simplification (making backend the single source of truth), we need to review and update all existing tests to ensure they reflect the new architecture. Significant changes were made to both frontend and backend:

**Backend Changes:**
- New `preview-service` Edge Function (calculates deadline internally)
- Updated `super-service` Edge Function (calculates deadline internally, no longer accepts `weekStartDate`)
- Updated `rpc_create_commitment` RPC function (accepts optional `p_deadline_timestamp` for testing mode)
- Added `week_end_timestamp` column to `commitments` table (for testing mode precision)
- Updated `bright-service` (settlement) to use `week_end_timestamp` when available

**Frontend Changes:**
- Removed `deadlineDate` parameter from `previewMaxCharge()` calls
- Removed `weekStartDate` parameter from `createCommitment()` calls
- Removed client-side deadline calculations from `fetchAuthorizationAmount()` and `lockInAndStartMonitoring()`
- iOS app now uses backend-calculated deadlines from responses

#### Impact

**Test Coverage**: ⚠️ High - Existing tests may be outdated and fail or test wrong behavior  
**Quality Assurance**: ⚠️ High - Need to ensure all tests reflect new architecture  
**Regression Risk**: ⚠️ Medium - Outdated tests could miss bugs or false positives

#### Required Test Review Areas

1. **Backend Tests**
   - Edge Function tests (`preview-service`, `super-service`)
   - RPC function tests (`rpc_preview_max_charge`, `rpc_create_commitment`)
   - Settlement tests (`bright-service`)
   - Deadline calculation tests (normal mode vs testing mode)
   - Database migration tests (`week_end_timestamp` column)

2. **Frontend Tests**
   - `BackendClient` tests (preview and commitment creation)
   - `AppModel` tests (authorization amount fetching)
   - `AuthorizationView` tests (commitment creation flow)
   - Deadline parsing tests (ISO 8601 vs date-only formats)
   - Testing mode vs normal mode behavior tests

3. **Integration Tests**
   - End-to-end commitment creation flow
   - Preview → Commitment deadline consistency
   - Testing mode compressed timeline tests
   - Normal mode Monday noon deadline tests
   - Settlement process with new deadline structure

4. **Test Data & Fixtures**
   - Update test fixtures to match new request/response formats
   - Remove deadline parameters from test calls
   - Update expected responses to include backend-calculated deadlines
   - Add test cases for `week_end_timestamp` in testing mode

#### Proposed Review Steps

1. **Inventory All Tests**
   - List all test files (backend and frontend)
   - Identify tests that reference deadline calculations
   - Identify tests that call `previewMaxCharge()` or `createCommitment()`
   - Identify tests that check deadline values

2. **Update Test Cases**
   - Remove deadline parameters from test calls
   - Update assertions to check backend-calculated deadlines
   - Add test cases for testing mode vs normal mode
   - Update test fixtures to match new API signatures

3. **Verify Test Coverage**
   - Ensure all new functionality is tested
   - Verify edge cases are covered (testing mode, normal mode, DST transitions)
   - Check that deadline calculation logic is tested
   - Verify backward compatibility (if applicable)

4. **Run Test Suite**
   - Execute all tests and fix failures
   - Verify tests pass in both testing and normal modes
   - Check for any false positives or negatives
   - Ensure test performance is acceptable

5. **Documentation**
   - Update test documentation to reflect new architecture
   - Document testing mode vs normal mode test procedures
   - Update test setup instructions if needed

#### Code Locations

**Backend Tests:**
- Edge Function tests (if any)
- RPC function tests (if any)
- Integration test scripts
- Test fixtures and mock data

**Frontend Tests:**
- iOS unit tests (if any)
- Integration tests
- Test fixtures

**Test Documentation:**
- Test guides and procedures
- Test setup instructions
- Test data requirements

#### Testing

1. Run existing test suite and identify failures
2. Update failing tests to match new architecture
3. Add new tests for new functionality
4. Verify all tests pass in both testing and normal modes
5. Check test coverage metrics
6. Review test documentation for accuracy

**Priority**: High  
**Timeline**: Before production deployment (critical for quality assurance)

**Related Documentation:**
- `docs/BACKEND_CALCULATES_DEADLINE_TESTING_GUIDE.md` - Testing guide for new architecture
- `docs/TEST_6_VERIFICATION_REPORT.md` - Verification that deadline calculations removed from iOS app
- `docs/BACKEND_ALWAYS_CALCULATES_DEADLINE_ANALYSIS.md` - Analysis of changes

---

### 23. Usage Sync Security: Prevent Usage Decrease Manipulation

**Status**: TODO  
**Severity**: High (Security/Financial)  
**Date Identified**: 2026-01-17  
**Phase**: V1.0 Finalization

#### Description

The current usage sync implementation allows users to potentially reduce their penalties by sending lower usage values. The backend accepts any value sent by the app without validation that usage can only increase.

**Current Behavior**:
- Usage entries are synced throughout the week (good - creates audit trail)
- Entries are only marked as "synced" in app after deadline (good - allows re-sync as usage increases)
- Backend uses `ON CONFLICT ... DO UPDATE SET used_minutes = EXCLUDED.used_minutes` (⚠️ **VULNERABILITY** - accepts any value)

**Security Risk**:
- User could modify App Group data to show lower usage
- User syncs manipulated data before deadline
- Backend accepts lower value (no validation)
- Penalty is incorrectly reduced

#### Impact

**Financial**: ⚠️ High - Users could reduce penalties by manipulating usage data  
**Security**: ⚠️ High - No validation prevents data manipulation  
**Data Integrity**: ⚠️ Medium - Incorrect usage values affect settlement accuracy

#### Proposed Fix

**Add Backend Validation** in `rpc_sync_daily_usage.sql`:

```sql
ON CONFLICT (user_id, date, commitment_id)
DO UPDATE SET
  -- Only update if new value is greater than existing value
  used_minutes = GREATEST(
    public.daily_usage.used_minutes,  -- Keep existing if higher
    EXCLUDED.used_minutes             -- Use new if higher
  ),
  ...
```

**Additional Enhancements** (Recommended):
1. Add suspicious activity logging when usage decreases (even if rejected)
2. Add usage progression validation (flag extreme increases)
3. Keep current approach (sync throughout week) - it's more secure than only syncing after deadline

#### Code Locations

- `supabase/remote_rpcs/rpc_sync_daily_usage.sql` - Add validation in `ON CONFLICT` clause
- Consider adding `suspicious_activity_log` table for tracking

#### Testing

1. Test usage decrease prevention:
   - Sync usage: 60 minutes
   - Try to sync lower value: 30 minutes
   - Verify backend keeps 60 minutes (doesn't decrease)

2. Test normal usage increase:
   - Sync usage: 60 minutes
   - Sync higher value: 120 minutes
   - Verify backend accepts 120 minutes

3. Test edge cases:
   - What happens on first sync (no existing value)?
   - What happens if usage stays the same?
   - What happens if user clears app data?

#### Related Documentation

- `docs/USAGE_SYNC_SECURITY_ANALYSIS.md` - Comprehensive security analysis
- `supabase/remote_rpcs/rpc_sync_daily_usage.sql` - Current implementation

**Priority**: High  
**Timeline**: Before production deployment (critical for security)

---

### 24. Production Secrets Setup for quick-handler Edge Function

**Status**: TODO  
**Severity**: High (Production Readiness)  
**Date Identified**: 2026-01-17  
**Phase**: V1.0 Finalization

#### Description

Set all production secrets for the `quick-handler` Edge Function. Currently, only staging secrets are configured. Production needs the same secrets set before deployment.

#### Required Production Secrets

Set the following secrets for `quick-handler` Edge Function in **PRODUCTION**:

1. **PRODUCTION_SUPABASE_SECRET_KEY** - Production Supabase secret key
2. **STRIPE_SECRET_KEY** - Production Stripe secret key (or `STRIPE_SECRET_KEY_PROD` if using separate test/prod)
3. **RECONCILIATION_SECRET** - Should already be set (same for staging and production)
4. **SUPABASE_URL** - Automatically available (reserved, cannot be set manually)

**Note**: Currently only staging secrets are set. Production secrets need to be configured before deploying to production.

**Reference**: Match the secrets pattern used by `bright-service` Edge Function.

#### Current Status

**Staging**: ✅ Complete
- `STAGING_SUPABASE_SECRET_KEY` ✅ Set
- `STAGING_STRIPE_SECRET_KEY` ✅ Set
- `RECONCILIATION_SECRET` ✅ Set

**Production**: ⏳ Pending
- `PRODUCTION_SUPABASE_SECRET_KEY` ⏳ Needs to be set
- `STRIPE_SECRET_KEY` ⏳ Needs to be set
- `RECONCILIATION_SECRET` ⏳ Verify if set

#### Impact

**Production Readiness**: ⚠️ High - `quick-handler` will fail without production secrets  
**Functionality**: ⚠️ High - Reconciliation process will not work in production  
**Financial**: ⚠️ High - Reconciliation is critical for accurate charges/refunds

#### How to Set

Use Supabase CLI:
```bash
supabase secrets set PRODUCTION_SUPABASE_SECRET_KEY="<value>" --project-ref <production-ref>
supabase secrets set STRIPE_SECRET_KEY="<value>" --project-ref <production-ref>
supabase secrets set RECONCILIATION_SECRET="<value>" --project-ref <production-ref>
```

Or via Supabase Dashboard → Edge Functions → quick-handler → Secrets

**Priority**: High  
**Timeline**: Before production deployment (critical for reconciliation process)

---

### 25. Settlement Safety Improvements (Priority 4)

**Status**: TODO  
**Severity**: Medium (Financial/Operational)  
**Date Identified**: 2026-01-18  
**Phase**: V1.0 Finalization

#### Description

Add idempotency keys, settlement attempt tracking, and retry logic to the settlement process to prevent duplicate charges and handle partial failures gracefully. This becomes critical as the user base grows (50+ users per week).

**Priority**: Medium  
**Timeline**: Fix soon (before reaching 50+ users per week)

---

### 26. Grace Period Storage (Priority 4) - TEST FIRST THING TOMORROW

**Status**: ✅ Implemented - Needs Testing  
**Severity**: Medium (Data Accuracy)  
**Date Identified**: 2026-01-18  
**Phase**: V1.0 Finalization

#### Description

Updated `rpc_create_commitment` to calculate and store `week_grace_expires_at` explicitly in the database. This eliminates runtime calculation errors and provides an audit trail.

**Implementation Complete**: ✅
- Function updated to calculate grace deadline
- Stores `week_grace_expires_at` for both testing mode (1 minute) and normal mode (Tuesday 12:00 ET)

**⚠️ ACTION REQUIRED - FIRST THING TOMORROW (2026-01-19):**
1. Deploy the updated `rpc_create_commitment` function
2. Test in testing mode (verify 1 minute grace period)
3. Test in normal mode (verify Tuesday 12:00 ET grace period)
4. Verify settlement function uses stored value

**Test Resources:**
- Test script: `supabase/sql-drafts/test_grace_period_storage.sql`
- Detailed guide: `docs/TEST_GRACE_PERIOD_STORAGE.md`

**Priority**: High (Test immediately after deployment)  
**Timeline**: Test first thing tomorrow (2026-01-19)

---

### 27. Dynamic Exchange Rate for Stripe Minimum Charge

**Status**: TODO  
**Date Identified**: 2026-01-21

At some point, we need to implement dynamic exchange rate calculation for the Stripe minimum charge. Currently using a static 62 cent minimum, but the Stripe account uses EUR settlement (50 EUR cent minimum), so we should dynamically convert 50 EUR cents to USD based on current exchange rates.

**Priority**: Low  
**Timeline**: Future enhancement

---

### 28. Hardcoded Configuration Values - Environment Dependency Issues

**Status**: TODO  
**Severity**: High (Production Readiness / Security)  
**Date Identified**: 2026-01-21  
**Phase**: V1.0 Finalization

#### Description

Multiple hardcoded configuration values throughout the codebase should be environment-dependent or use `app_config` table. This creates risks when deploying to production and makes configuration management difficult.

#### Critical Issues Found

1. **`call_weekly_close.sql` - Hardcoded Staging URL** (🔴 CRITICAL)
   - **Location**: `supabase/remote_rpcs/call_weekly_close.sql` (line 17)
   - **Issue**: Hardcoded staging URL `https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close`
   - **Impact**: Will call staging URL in production, breaking weekly close functionality
   - **Fix**: Use `app_config.supabase_url` (like `process_reconciliation_queue` does)
   - **Also**: Currently uses `current_setting('app.settings.service_role_key')` - should use `app_config` for consistency

2. **iOS `Config.swift` - Production Stripe Key Still Test Key** (🔴 CRITICAL)
   - **Location**: `payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/Config.swift` (line 101)
   - **Issue**: `livePublishableKey` is still a test key (`pk_test_...`) with TODO comment
   - **Impact**: Production will use test Stripe keys instead of live keys
   - **Fix**: Replace with real `pk_live_...` key before production launch

3. **Hardcoded Timeout Values** (🟡 HIGH)
   - **Location**: `call_weekly_close.sql` (line 23), `process_reconciliation_queue.sql`
   - **Issue**: Hardcoded `30000` (30 seconds) timeout
   - **Impact**: Cannot tune timeouts without code changes
   - **Fix**: Move to `app_config` table (e.g., `http_timeout_ms`)

4. **Hardcoded Retry Limits** (🟡 HIGH)
   - **Location**: `process_reconciliation_queue.sql` (line 28)
   - **Issue**: Hardcoded `max_retries integer := 3`
   - **Impact**: Cannot tune retry behavior without code changes
   - **Fix**: Move to `app_config` table (e.g., `max_reconciliation_retries`)

5. **Hardcoded "Stuck Processing" Threshold** (🟢 MEDIUM)
   - **Location**: Multiple SQL files
   - **Issue**: Hardcoded `INTERVAL '5 minutes'` for stuck processing detection
   - **Impact**: Cannot tune threshold without code changes
   - **Fix**: Move to `app_config` table (e.g., `stuck_processing_threshold_minutes`)

6. **iOS Config.swift - Hardcoded Supabase URLs** (🟢 MEDIUM)
   - **Location**: `Config.swift` (lines 60-65)
   - **Issue**: URLs and keys hardcoded (though environment-aware via build config)
   - **Impact**: Less flexible, harder to manage secrets
   - **Fix**: Consider build-time configuration or Info.plist approach

#### Impact

**Production Readiness**: ⚠️ High - `call_weekly_close` will break in production  
**Security**: ⚠️ High - Production Stripe key is test key  
**Maintainability**: ⚠️ Medium - Hardcoded values make configuration management difficult  
**Operational**: ⚠️ Medium - Cannot tune timeouts/retries without code changes

#### Proposed Fix Priority

**Phase 1: Critical (Before Production)**
1. Fix `call_weekly_close.sql` to use `app_config.supabase_url` and `app_config.service_role_key`
2. Replace Stripe production key in `Config.swift` with real `pk_live_...` key

**Phase 2: High (Soon)**
3. Move timeout values to `app_config`
4. Move retry limits to `app_config`
5. Update all functions to use configurable values

**Phase 3: Medium (Nice to Have)**
6. Move stuck processing threshold to `app_config`
7. Consider iOS build-time configuration improvements

#### Migration Checklist

Before deploying Fix 1:
- [ ] Verify `app_config` table has `supabase_url` in staging
- [ ] Verify `app_config` table has `supabase_url` in production
- [ ] Verify `app_config` table has `service_role_key` in staging
- [ ] Verify `app_config` table has `service_role_key` in production
- [ ] Test `call_weekly_close()` function in staging after update
- [ ] Test `call_weekly_close()` function in production after update

#### Code Locations

- `supabase/remote_rpcs/call_weekly_close.sql` - Main fix needed
- `payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/Config.swift` - Stripe key fix
- `supabase/remote_rpcs/process_reconciliation_queue.sql` - Retry/timeout config
- Multiple SQL files - Stuck processing threshold

#### Related Documentation

- See comprehensive analysis in conversation history (2026-01-21)
- Pattern to follow: `process_reconciliation_queue.sql` already uses `app_config` correctly

**Priority**: High  
**Timeline**: Fix Phase 1 before production deployment (critical), Phase 2 soon after

---

## Notes

- All issues documented here are **non-blocking** - development can continue
- Issues are prioritized by severity and impact
- Fix timeline is flexible and based on available resources
- Tasks in "Other Tasks & Readiness Items" should be completed before V1.0 release
