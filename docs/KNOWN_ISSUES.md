# Known Issues & Bugs

This document tracks known bugs and issues that are not critical enough to block development but should be addressed in the future.

---

## App Startup Delay

**Status**: Known Issue - Performance  
**Severity**: Medium (User Experience)  
**Date Identified**: 2025-12-11  
**Phase**: App Initialization

### Description

The app takes approximately one minute to show the landing screen (PayAttentionClub logo) when launched on a physical device. This delay occurs during app initialization, likely due to network operations or synchronization tasks running on startup.

### Symptoms

- App launches but shows loading screen for ~60 seconds
- Landing screen appears after significant delay
- Occurs on physical devices (may not reproduce in simulator)
- User experiences long wait time before app becomes interactive

### Impact

**User Experience**: ⚠️ Medium – Users wait ~60 seconds before seeing the main screen  
**Product**: ⚠️ Medium – Poor first impression, may cause users to think app is frozen  
**Functional**: ✅ None – App eventually loads and works correctly

### Root Cause Analysis

**Suspected Causes**:
1. Network sync operation (`UsageSyncManager.syncToBackend()`) may be timing out (default URLSession timeout is 60 seconds)
2. Supabase client initialization may be slow on first launch
3. Network connectivity issues to staging/production environment
4. Synchronous operations blocking main thread during initialization

**Attempted Fixes**:
- Added 5-second timeout to sync operation
- Made sync non-blocking (runs in background)
- Moved navigation before sync to prevent blocking
- Issue persists, suggesting deeper network or initialization problem

### Code Locations

- `AppModel.swift`: `finishInitialization()` method
- `UsageSyncManager.swift`: `syncToBackend()` method
- `BackendClient.swift`: Supabase client initialization

### When to Fix

**Priority**: Medium  
**Suggested Timeline**: Before production release, or when:
- User complaints about slow startup increase
- Performance becomes a blocker for user adoption
- Root cause can be identified through profiling

### Proposed Fix

1. **Profile app startup** using Instruments to identify exact bottleneck
2. **Add startup logging** to track which operation is taking time
3. **Consider lazy initialization** of network clients (only when needed)
4. **Skip sync on first launch** if user isn't authenticated
5. **Add progress indicator** during startup to show app is working
6. **Investigate Supabase client** initialization time

### Testing

- Measure startup time on physical device
- Test with network disabled (airplane mode) to isolate network issues
- Test with staging vs production environments
- Profile with Instruments to identify slow operations

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

## Rename Supabase Key Variables to Match New Naming Convention

**Status**: ✅ **RESOLVED** - Completed 2025-12-12  
**Severity**: Low (Naming Consistency)  
**Date Identified**: 2025-12-12  
**Date Resolved**: 2025-12-12

### Description

We are already using Supabase's new publishable/secret key system, but our variable names still use the legacy naming convention. We need to rename:
- `SUPABASE_ANON_KEY` → `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` → `SUPABASE_SECRET_KEY`

### Resolution

✅ **Completed**: All variable names have been updated across the codebase:
- Swift code: `anonKey` → `publishableKey` in `Config.swift` and `BackendClient.swift`
- Shell scripts: All references updated to use `SUPABASE_SECRET_KEY` and `SUPABASE_PUBLISHABLE_KEY`
- TypeScript/Deno tests: Updated `config.ts` to use new naming
- Edge Functions: Updated `weekly-close/index.ts` to use `SUPABASE_SECRET_KEY`

**Note**: The `.env` file needs to be manually updated with the new variable names (not committed to git).

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

## Authorization Fee Calculation Incorrect

**Status**: Known Issue - Critical Bug  
**Severity**: High (Financial/User Experience)  
**Date Identified**: 2025-12-10  
**Phase**: Commitment Creation Flow

### Description

The calculation of the authorization fee when making a commitment is way too high or way off. This affects the amount charged to users when they create a commitment, potentially charging significantly more than intended.

### Symptoms

- Authorization fee displayed/charged is incorrect (too high)
- Users may be overcharged when creating commitments
- Fee calculation does not match expected values

### Impact

**Financial**: ⚠️ High – Users may be incorrectly charged  
**User Experience**: ⚠️ High – Users see incorrect fees, may abandon commitment creation  
**Product**: ⚠️ High – Core payment flow is broken  
**Data Integrity**: ⚠️ Medium – Incorrect charges may be recorded

### Code Locations

- Commitment creation flow (likely in `AppModel.swift` or commitment-related views)
- Payment/Stripe integration code
- Authorization fee calculation logic

### When to Fix

**Priority**: High  
**Suggested Timeline**: Fix immediately - this affects core payment functionality

### Proposed Fix

1. Review authorization fee calculation logic
2. Compare calculated values with expected/design specifications
3. Identify where the calculation goes wrong (formula error, unit conversion, etc.)
4. Fix the calculation and add unit tests to prevent regression
5. Verify with test commitments before deploying

### Testing

- Create test commitments and verify authorization fees match expected amounts
- Test with various commitment amounts/parameters
- Verify Stripe charges match calculated authorization fees

---

## App Selection Group Display Issue

**Status**: Known Issue - UI/UX Bug  
**Severity**: Medium (User Experience)  
**Date Identified**: 2025-12-11  
**Phase**: App Selection Flow

### Description

When selecting the "Select apps to limit" button, users sometimes see a list of app groups. When opening one of these groups for the first time, the apps within that group do not display. Users must exit the screen, press the "Select apps to limit" button again, and then open the group a second time for the apps to appear.

### Symptoms

- First attempt: User taps "Select apps to limit" → sees groups → opens a group → apps don't show
- Second attempt: User exits screen → taps "Select apps to limit" again → opens same group → apps now display correctly
- Inconsistent behavior - doesn't happen every time
- Requires user to perform the action twice to see apps in groups

### Impact

**User Experience**: ⚠️ Medium – Users must repeat the action to see apps, creating confusion and friction  
**Product**: ⚠️ Medium – Poor UX may cause users to think the feature is broken  
**Functional**: ✅ None – Feature works correctly on second attempt  
**Data Integrity**: ✅ None – No data loss, just display issue

### Root Cause Analysis

**Suspected Causes**:
1. Race condition in loading app groups/apps data
2. Initial state not properly initialized when group is first opened
3. FamilyActivityPicker or app selection view not refreshing properly on first load
4. Async data loading completing after UI renders

### Code Locations

- App selection view (likely related to FamilyActivityPicker or app limiting flow)
- Group/app data loading logic
- Navigation/view state management for app selection screen

### When to Fix

**Priority**: Medium  
**Suggested Timeline**: Before production release, or when:
- User complaints about the feature increase
- UX becomes a blocker for user adoption
- Root cause can be identified through debugging

### Proposed Fix

1. **Investigate app group loading logic** - Check if data is loaded before UI renders
2. **Add proper state management** - Ensure view state is correctly initialized when groups are opened
3. **Add loading indicators** - Show loading state while apps are being fetched
4. **Review FamilyActivityPicker integration** - Check if there's a refresh or reload mechanism needed
5. **Add logging** - Track when groups are opened and when apps are loaded to identify timing issues
6. **Consider preloading** - Load app data when groups are displayed, not when opened

### Testing

- Test app selection flow multiple times to reproduce the issue
- Verify apps display correctly on first group open attempt
- Test with different numbers of apps/groups
- Test on physical devices (may not reproduce in simulator)
- Verify fix works consistently across multiple attempts

---

## Test Harness Needs Update

**Status**: Known Issue - Technical Debt  
**Severity**: Medium (Development Velocity)  
**Date Identified**: 2025-12-14  
**Phase**: Testing Infrastructure

### Description

The test harness (backend Deno tests and iOS unit tests) may be out of sync with the actual codebase after recent major changes including:
- Authorization fee calculation moved to backend (`calculate_max_charge_cents`, `rpc_preview_max_charge`)
- Environment variable naming changes (`ANON_KEY` → `PUBLISHABLE_KEY`, `SERVICE_ROLE_KEY` → `SECRET_KEY`)
- New RPC functions added (`rpc_execute_sql`, `rpc_list_cron_jobs`, `rpc_get_cron_history`, `rpc_verify_setup`)
- Updated `rpc_create_commitment` to use shared calculation function
- Frontend `AppModel` changes (async `fetchAuthorizationAmount()` vs old sync method)
- `PenaltyCalculator.calculateAuthorizationAmount()` deprecated

### Tests Potentially Affected

**Backend (Deno)**:
- `supabase/tests/test_create_commitment.ts` - May need update for new calculation logic
- `supabase/tests/reset_my_user.ts` - ✅ Already updated for `SECRET_KEY` naming
- Other test files may reference old function signatures or env vars

**Frontend (iOS)**:
- `AppModelTests.swift` - Tests `PenaltyCalculator.calculateAuthorizationAmount()` which is now deprecated
- `BackendClientTests.swift` - May need tests for new `previewMaxCharge()` method
- Tests may fail if they expect old return values or method signatures

### Impact

**Development**: ⚠️ Medium – Tests may fail or give false positives  
**Quality**: ⚠️ Medium – Reduced confidence in code changes  
**CI/CD**: ⚠️ Low – No automated CI yet, but will block future setup

### Action Required

1. **Run all backend tests** and document failures:
   ```bash
   ./scripts/run_backend_tests.sh staging
   ```

2. **Run iOS unit tests** in Xcode and document failures:
   - Product → Test (⌘U)

3. **Update failing tests** to match new function signatures and expected values

4. **Add new tests** for:
   - `rpc_preview_max_charge` - verify returns correct bounded values
   - `BackendClient.previewMaxCharge()` - verify iOS can call the preview RPC
   - `calculate_max_charge_cents` - verify bounds ($5 min, $1000 max)

5. **Remove/update deprecated tests** that test old calculation logic

### When to Fix

**Priority**: Medium  
**Suggested Timeline**: Before next major feature work, to ensure test coverage is reliable

---

## Git Branching & CI/CD Pipeline Setup

**Status**: Known Issue - Infrastructure  
**Severity**: Medium (Development Process)  
**Date Identified**: 2025-12-14  
**Phase**: Development Infrastructure

### Description

Currently all development happens directly on `main` branch with no separation between staging and production code. We need to implement proper Git branching strategy and CI/CD pipeline with automated testing and secrets checking before code reaches the remote repository.

### Current State

- ❌ Single `main` branch for everything
- ❌ No automated testing before push
- ❌ No automated secrets scanning
- ❌ Manual deployment to staging/production
- ❌ No branch protection rules

### Required Setup

**1. Git Branching Strategy**
- `main` branch = production-ready code only
- `develop` branch = staging/integration branch
- `feat/*` branches = feature development
- `fix/*` branches = bug fixes
- `hotfix/*` branches = urgent production fixes

**2. Pre-Push Hooks (Local)**
- Run secrets scan before any push
- Block push if secrets detected
- Optionally run tests before push

**3. Secrets Scanning**
Must check for and block:
| Pattern | Description |
|---------|-------------|
| `sk_live_*` | Stripe live secret key |
| `sk_test_*` | Stripe test secret key |
| `whsec_*` | Stripe webhook secret |
| `eyJ*` (long JWT) | Service role keys |
| `sbp_*` | Supabase project tokens |
| Passwords in URLs | Database connection strings |

**4. CI/CD Pipeline (GitHub Actions)**
- On PR to `develop`: Run tests, block merge if failing
- On PR to `main`: Run tests + secrets scan, require approval
- On merge to `develop`: Auto-deploy to staging
- On merge to `main`: Auto-deploy to production (with approval gate)

### Implementation Steps

1. **Create `develop` branch**
   ```bash
   git checkout -b develop
   git push -u origin develop
   ```

2. **Create `scripts/check_secrets.sh`**
   - Scan staged files for secret patterns
   - Exit with error if secrets found
   - Print clear message about what was found

3. **Set up Git pre-push hook**
   ```bash
   # .git/hooks/pre-push
   #!/bin/bash
   ./scripts/check_secrets.sh || exit 1
   ```

4. **Add branch protection on GitHub**
   - Settings → Branches → Add rule for `main`
   - Require PR reviews
   - Require status checks to pass

5. **Create GitHub Actions workflow** (`.github/workflows/ci.yml`)
   - Run on PR to `main` and `develop`
   - Run backend tests
   - Run secrets scan
   - Report results

### Impact

**Development**: ⚠️ Medium – Risk of pushing secrets or broken code  
**Security**: ⚠️ High – No automated secrets scanning  
**Quality**: ⚠️ Medium – No automated test gates  
**Collaboration**: ⚠️ Low – Solo dev currently, but blocks future team growth

### When to Fix

**Priority**: Medium  
**Suggested Timeline**: Before adding team members or before production launch

### Related Documentation

- `DEPLOYMENT_WORKFLOW.md` - Contains the planned workflow (not yet implemented)
- `docs/AUTHORIZATION_FEE_FIX.md` - Example of changes that should go through proper flow

---

## Future Issues

_Add new issues here as they are discovered..._

---

## Ops: Loops.so Secrets Must Match in Production and Staging

**Status**: Known Issue – Configuration  
**Severity**: Low (Ops/Testing)  
**Date Identified**: 2025-12-12  

### Description

The Loops.so API secrets must be identical in both **production** and **staging** Supabase environments. Since Loops.so is a single service (no separate staging environment), both Supabase projects need to use the same Loops API key to send emails.

### Action Required

Ensure the `LOOPS_API_KEY` (or equivalent secret name) is set to the same value in:
- Production Supabase project secrets
- Staging Supabase project secrets

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

