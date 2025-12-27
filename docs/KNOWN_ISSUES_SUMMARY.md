# Known Issues Summary

Quick reference list of all known issues, bugs, and missing items in the Pay Attention Club app.

---

## 🔴 CRITICAL ISSUES (Must Fix)

### 1. Security: Service Role Key Embedded in SQL
- **Status**: Known Issue - Security Hygiene
- **Severity**: High (Secrets Exposure)
- **Location**: `call_weekly_close` function body
- **Issue**: Supabase `service_role` key stored in plain text in SQL
- **Action**: Rotate key, move to DB setting, update function
- **File**: `docs/KNOWN_ISSUES.md` (line 220)

### 2. Missing RPC Function: `rpc_update_monitoring_status`
- **Status**: ❌ NOT IMPLEMENTED
- **Severity**: High (Functionality)
- **Location**: Database RPC functions
- **Issue**: iOS app needs this to handle Screen Time revocation
- **Action**: Create and deploy function
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 41)

### 3. Missing iOS Integration: Monitoring Revocation Handler
- **Status**: ❌ NOT IMPLEMENTED
- **Severity**: High (Functionality)
- **Location**: iOS app
- **Issue**: App doesn't call `rpc_update_monitoring_status` when Screen Time is revoked
- **Action**: Add revocation detection and RPC call
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 268)

### 4. Fixed Functions Not Deployed
- **Status**: ⚠️ Fixed locally, not deployed
- **Severity**: High (Data Integrity)
- **Location**: Supabase database
- **Issue**: Fixed versions of functions exist but not deployed:
  - `weekly-close` (uses `week_end_date` instead of `week_start_date`)
  - `rpc_create_commitment_updated.sql`
  - `rpc_report_usage_fixed.sql`
- **Action**: Deploy all fixed versions
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 153)

---

## 🟡 MEDIUM PRIORITY ISSUES

### 5. Multiple Concurrent Syncs Issue
- **Status**: Known Issue - Non-Critical
- **Severity**: Medium (Performance/Cost)
- **Location**: `UsageSyncManager.swift`, `BackendClient.swift`
- **Issue**: 3-5 sync operations run concurrently instead of being serialized
- **Impact**: 3-5x more network requests and database writes than necessary
- **Action**: Use Swift `actor` for async-safe state management
- **File**: `docs/KNOWN_ISSUES.md` (line 7)

### 6. Reconciliation Guardrails Depend on Operator Discipline
- **Status**: Known Issue – Operational Risk
- **Severity**: Medium (Financial/Support)
- **Location**: `settlement-reconcile` scheduler
- **Issue**: Can be misconfigured (large payloads, no dry run) increasing blast radius
- **Impact**: Risk of unintended bulk refunds/charges
- **Action**: Add automated alerting, safer batching, UI tooling
- **File**: `docs/KNOWN_ISSUES.md` (line 99)

### 7. Email Contact Limitation with Sign in with Apple
- **Status**: Known Issue - Potential Product Limitation
- **Severity**: Medium (Growth & Support)
- **Location**: Authentication flow
- **Issue**: Users only provide Apple relay emails, no real contact email collected
- **Impact**: Transactional emails may be filtered, support follow-ups difficult
- **Action**: Prompt users to optionally share real email post-onboarding
- **File**: `docs/KNOWN_ISSUES.md` (line 295)

### 8. Cron Job Setup Needs Verification
- **Status**: ⚠️ Script exists, needs verification
- **Severity**: Medium (Functionality)
- **Location**: Supabase cron configuration
- **Issue**: Weekly close cron may not be active
- **Action**: Verify cron job is set up and active
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 167)

### 9. Stripe Webhook Function Needs Update
- **Status**: ⚠️ Minor fix needed
- **Severity**: Medium (Consistency)
- **Location**: `supabase/functions/stripe-webhook/stripe-webhook.ts`
- **Issue**: Uses `STRIPE_SECRET_KEY` directly, should use test key with fallback
- **Action**: Update to match other functions' pattern
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 197)

---

## 🟢 LOW PRIORITY ISSUES

### 10. App Startup Loading Screen Delay
- **Status**: Known Issue - UX/Performance
- **Severity**: Low (User Experience)
- **Location**: App initialization, `payattentionclub_app_1_1App.swift`, `RootRouterView.swift`
- **Issue**: Prolonged white/loading screen before logo appears on app launch
- **Impact**: Poor first impression, app feels slow to launch
- **Action**: Optimize startup sequence, show splash screen immediately, profile bottlenecks
- **File**: `docs/KNOWN_ISSUES.md` (Phase 1: App Startup Loading Screen Delay)

### 11. FamilyActivityPicker Permission Screen Delay
- **Status**: Known Issue - UX/Performance
- **Severity**: Low (User Experience)
- **Location**: `SetupView.swift`, app selection button
- **Issue**: 2-3 second delay before permission screen appears when pressing "Select Apps" button for first time
- **Impact**: Feels unresponsive, users may tap button multiple times
- **Action**: Add immediate visual feedback, show loading indicator, disable button during delay
- **File**: `docs/KNOWN_ISSUES.md` (Phase 1: FamilyActivityPicker Permission Screen Delay)

### 12. Weekly Grace Window Needs Pre-Week Buffer
- **Status**: Known Issue - UX/Behavioral
- **Severity**: Low (User Expectation)
- **Location**: `UsageTracker.swift`, commitment evaluation logic
- **Issue**: No 2-4 hour buffer before week ends (only 24-hour post-week grace)
- **Impact**: Last-minute usage still affects week totals
- **Action**: Add pre-week grace window (2-4 hours)
- **File**: `docs/KNOWN_ISSUES.md` (line 244)

### 13. Missing Dev Button: Admin Close Week Now
- **Status**: ⚠️ Backend exists, iOS UI missing
- **Severity**: Low (Developer Experience)
- **Location**: iOS app UI
- **Issue**: Backend function exists but no iOS UI to trigger it
- **Action**: Add hidden dev button (low priority)
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 280)

### 14. RLS Policies Need Verification
- **Status**: ⚠️ Needs verification
- **Severity**: Low (Security)
- **Location**: Supabase database
- **Issue**: Policies exist but should be verified active
- **Action**: Verify all RLS policies are active
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 203)

### 15. Test Isolation Needs Testing
- **Status**: ⚠️ Needs testing
- **Severity**: Low (Security)
- **Location**: Database RLS
- **Issue**: Should verify no cross-user visibility
- **Action**: Create test account and verify isolation
- **File**: `docs/BACKEND_MISSING_ITEMS.md` (line 221)

---

## 📋 V1.0 FINALIZATION TODO ITEMS

### High Priority
1. **Handle Screen Time revocation** - Document behavior when FamilyControls permission is revoked mid-week
2. **Testing rig** - Build seed → cron → verify harness for weekly settlement scenarios
3. **Known issues audit** - Revisit `KNOWN_ISSUES.md`, confirm statuses, close outdated items
4. **Env separation** - Distinct staging + production Supabase projects
5. **TestFlight readiness** - Finish Apple entitlement approvals, prepare provisioning profiles

### Medium Priority
6. **UI polish** - Final pass on Authorization/Monitor/Bulletin views
7. **Monitoring & alerts** - Structured logging, alert hooks for failures
8. **Config sanity check** - Tooling to verify Supabase/Stripe env vars before deploy
9. **Security review** - Audit auth scopes, secret storage, request logging

### Low Priority
10. **Automated data cleanup** - Scripts to reset seeded data after QA runs
11. **App Group heartbeat** - Diagnostic screen to confirm DeviceActivity monitor is writing
12. **Docs refresh** - Update README/architecture with Tuesday-noon settlement cadence
13. **Code cleanup** - Remove debug logs, tidy unused files, enforce formatting
14. **Stripe mapping clarity** - Explicit staging ↔ sandbox, production ↔ live mapping

**File**: `docs/V1.0_FINALIZATION_TODO.md`

---

## 📊 Summary by Category

### Security Issues: 2
- Service role key in SQL (🔴 Critical)
- RLS policies need verification (🟢 Low)

### Missing Functionality: 3
- `rpc_update_monitoring_status` function (🔴 Critical)
- Monitoring revocation handler (🔴 Critical)
- Dev button for admin close (🟢 Low)

### Deployment Issues: 1
- Fixed functions not deployed (🔴 Critical)

### Performance/Cost Issues: 1
- Multiple concurrent syncs (🟡 Medium)

### Operational Risk: 1
- Reconciliation guardrails (🟡 Medium)

### Product/UX Issues: 4
- Email contact limitation (🟡 Medium)
- App startup loading delay (🟢 Low)
- FamilyActivityPicker permission delay (🟢 Low)
- Weekly grace window (🟢 Low)

### Verification Needed: 3
- Cron job setup (🟡 Medium)
- RLS policies (🟢 Low)
- Test isolation (🟢 Low)

### Code Quality: 1
- Stripe webhook function pattern (🟡 Medium)

---

## 🎯 Recommended Action Order

1. **Fix security issue** (service role key) - 🔴 Critical
2. **Create and deploy `rpc_update_monitoring_status`** - 🔴 Critical
3. **Add iOS monitoring revocation handler** - 🔴 Critical
4. **Deploy all fixed functions** - 🔴 Critical
5. **Fix concurrent syncs issue** - 🟡 Medium
6. **Verify cron job setup** - 🟡 Medium
7. **Add email collection prompt** - 🟡 Medium
8. **Update Stripe webhook function** - 🟡 Medium
9. **Add pre-week grace buffer** - 🟢 Low
10. **Complete V1.0 finalization items** - Various priorities

---

## 📝 Notes

- All issues in `KNOWN_ISSUES.md` are **non-blocking** - development can continue
- Issues are prioritized by severity and impact
- Fix timeline is flexible and based on available resources
- See individual issue files for detailed descriptions and proposed fixes


