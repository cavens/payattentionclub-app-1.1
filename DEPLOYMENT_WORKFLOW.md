# Deployment Workflow

This document describes the development, testing, and deployment workflow for the Pay Attention Club app.

## Environments

| Environment | Purpose | Supabase Project | iOS Build |
|-------------|---------|------------------|-----------|
| **Staging** | Testing before production | `auqujbppoytkeqdsgrbl` | DEBUG mode |
| **Production** | Live users | `whdftvcrtrsnefhprebj` | RELEASE mode |

## Git Branching Strategy

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Feature   │ --> │   Develop    │ --> │    Main      │
│   Branch    │     │  (Staging)   │     │ (Production) │
└─────────────┘     └─────────────┘     └─────────────┘
     │                    │                    │
     │                    │                    │
     v                    v                    v
  Local Dev          Staging Env          Production Env
```

| Branch | Supabase Environment | iOS Build Mode | Purpose |
|--------|---------------------|----------------|---------|
| `feat/*` | Local only | DEBUG | Feature development |
| `develop` | **Staging** | DEBUG | Integration testing |
| `main` | **Production** | RELEASE | Live users |

## Current Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Local Dev     │     │    Staging      │     │   Production    │
│   (Your Mac)    │     │   (Supabase)    │     │   (Supabase)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
    Code changes           Test here first          Live users
         │                       │                       │
         └───────────────────────┴───────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
              GitHub (develop)          GitHub (main)
              (Staging branch)          (Production branch)
```

---

## Recommended Workflow

### 1. DEVELOP (Local)

```bash
# Start from develop branch (staging)
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feat/my-feature

# Make code changes
# - Swift files in payattentionclub-app-1.1/
# - SQL/RPC in supabase/remote_rpcs/
# - Edge Functions in supabase/functions/
```

### 2. TEST ON STAGING

```bash
# Deploy SQL/RPC functions to staging
./scripts/deploy_to_staging.sh

# Build iOS in DEBUG mode (Xcode)
# - DEBUG mode automatically connects to staging
# - Test on device/simulator

# Run backend tests against staging
./scripts/run_backend_tests.sh staging
```

### 3. PRE-COMMIT SAFETY CHECK

```bash
# ⚠️ IMPORTANT: Check for secrets BEFORE committing!
./scripts/check_secrets.sh

# This scans for:
# - API keys (sk_live_, sk_test_, eyJ...)
# - Service role keys
# - Webhook secrets (whsec_)
# - Database passwords
# - Any hardcoded credentials
```

### 4. COMMIT & PUSH

```bash
# Only after staging tests pass AND secrets check passes!
git add -A
git commit -m "feat: description of changes"
git push origin feat/my-feature

# Create Pull Request: feat/my-feature → develop (staging)
```

### 5. MERGE TO DEVELOP (Staging)

```bash
# After PR approval (or directly for solo dev)
git checkout develop
git pull origin develop
git merge feat/my-feature
git push origin develop

# Deploy to staging Supabase
./scripts/deploy_to_staging.sh

# Test thoroughly in staging before proceeding
```

### 6. MERGE TO MAIN (Production)

```bash
# Only when staging is fully tested and ready!
git checkout main
git pull origin main
git merge develop
git push origin main
```

### 7. DEPLOY TO PRODUCTION

```bash
# Deploy SQL/RPC functions to production
./scripts/deploy_to_production.sh

# Deploy Edge Functions (manual in Supabase Dashboard)
# See: docs/EDGE_FUNCTION_DEPLOYMENT.md

# Verify in production
```

### 8. RELEASE (Optional)

```bash
# Tag the release
git tag -a v1.2.0 -m "Release 1.2.0"
git push origin v1.2.0

# Submit iOS to App Store (separate process)
```

---

## Deployment Scripts

### Deploy to Staging
```bash
./scripts/deploy_to_staging.sh
```
Deploys all SQL/RPC functions from `supabase/remote_rpcs/` to staging.

### Deploy to Production
```bash
./scripts/deploy_to_production.sh
```
Deploys all SQL/RPC functions from `supabase/remote_rpcs/` to production.

### Run Backend Tests
```bash
./scripts/run_backend_tests.sh staging      # Test against staging
./scripts/run_backend_tests.sh production   # Test against production (careful!)
```

---

## Key Concept: Git vs Deployment

**Git is for version control, NOT deployment.**

- ✅ Git stores code history and enables collaboration
- ❌ Git does NOT automatically deploy to Supabase
- ✅ We deploy directly from local to Supabase using scripts/API calls
- ✅ iOS builds happen locally in Xcode (Archive → App Store Connect)

**Deployment Flow:**
```
Local Code → Git (version control) → Local Script → Supabase (direct API)
Local Code → Git (version control) → Xcode Archive → App Store Connect
```

---

## Implementation Plan

### Essential Scripts (Priority)
| Task | Status | Description |
|------|--------|-------------|
| 3.1 | ⬜ | **CRITICAL**: Create `scripts/check_secrets.sh` - scan for exposed secrets |
| 2.1 | ⬜ | Create `scripts/deploy_to_staging.sh` - deploy SQL/RPC to staging |
| 2.2 | ⬜ | Create `scripts/deploy_to_production.sh` - deploy SQL/RPC to production |

### Optional Scripts
| Task | Status | Description |
|------|--------|-------------|
| 3.4 | ⬜ | Add git pre-push hook (auto-runs check_secrets.sh) |
| 3.2 | ⬜ | Create `scripts/test_staging.sh` - run tests against staging |

### Branch Setup
| Task | Status | Description |
|------|--------|-------------|
| 1.1 | ⬜ | Create `develop` branch for staging work |
| 1.2 | ⬜ | (Optional) Protect `main` branch on GitHub |

---

## Quick Reference

```bash
# === TYPICAL DEVELOPMENT CYCLE ===

# 1. Start feature from develop (staging branch)
git checkout develop && git pull
git checkout -b feat/my-feature

# 2. Make changes, deploy to staging
./scripts/deploy_to_staging.sh

# 3. Test in Xcode (DEBUG mode → staging)
# Build and run on device

# 4. Check for secrets, then commit
./scripts/check_secrets.sh
git add -A && git commit -m "feat: my feature"
git push origin feat/my-feature

# 5. Merge to develop (staging)
git checkout develop && git pull
git merge feat/my-feature && git push origin develop
./scripts/deploy_to_staging.sh  # Deploy to staging Supabase

# 6. After staging is tested, merge to main (production)
git checkout main && git pull
git merge develop && git push origin main

# 7. Deploy to production
./scripts/deploy_to_production.sh

# 8. Verify production works
```

---

## iOS Build Modes

| Build Mode | Environment | How to Build |
|------------|-------------|--------------|
| **DEBUG** | Staging | Xcode → Run (⌘R) |
| **RELEASE** | Production | Xcode → Product → Archive |

The environment is automatically selected in `Config.swift`:
```swift
#if DEBUG
    static let current: Environment = .staging
#else
    static let current: Environment = .production
#endif
```

---

## Edge Functions Deployment

Edge Functions currently require manual deployment via Supabase Dashboard:

1. Go to Supabase Dashboard → Edge Functions
2. Select the function to update
3. Copy-paste the new code from `supabase/functions/[name]/index.ts`
4. Click Deploy

**Functions to deploy:**
- `rapid-service` - SetupIntent confirmation
- `billing-status` - Check billing status
- `weekly-close` - Weekly settlement
- `bright-service` - Penalty charging

---

## Secrets Safety Check

### ⚠️ CRITICAL: Never Commit Secrets!

Before ANY commit, check for exposed secrets:

```bash
./scripts/check_secrets.sh
```

### What It Scans For

| Pattern | Description |
|---------|-------------|
| `sk_live_*` | Stripe live secret key |
| `sk_test_*` | Stripe test secret key |
| `whsec_*` | Stripe webhook secret |
| `eyJ*` (long) | JWT tokens (service role keys) |
| `sbp_*` | Supabase project tokens |
| Hardcoded passwords | Database connection strings |

### Files That Should NEVER Contain Secrets

- `*.swift` - iOS source code
- `*.sql` - SQL scripts
- `*.ts` - Edge Functions
- `*.md` - Documentation
- `*.sh` - Shell scripts (except reading from .env)

### Files That CAN Contain Secrets (gitignored)

- `.env` - Environment variables (in .gitignore)
- `*.p8` - Apple auth keys (in .gitignore)

### If Secrets Are Accidentally Committed

1. **Rotate the secret immediately** in Supabase/Stripe Dashboard
2. Remove from git history:
   ```bash
   ./scripts/remove_secrets_from_history.sh
   ```
3. Force push (coordinate with team if applicable)

---

## Rollback Procedure

If something breaks in production:

### 1. Rollback SQL/RPC
```bash
# Revert to previous commit
git checkout HEAD~1 -- supabase/remote_rpcs/[function].sql

# Deploy the old version
./scripts/deploy_to_production.sh
```

### 2. Rollback Edge Function
- Go to Supabase Dashboard → Edge Functions
- View deployment history
- Redeploy previous version

### 3. Rollback iOS
- App Store submissions can't be instantly rolled back
- Submit a new version with the fix
- Or use TestFlight for staged rollouts

---

## Important Notes

### Why Manual Deployment?

- **Supabase**: No built-in git integration, requires API calls from local machine
- **iOS**: Requires Xcode to build/archive, manual upload to App Store Connect
- **Control**: Manual deployment gives you full control over when/what gets deployed

### What We're NOT Doing

- ❌ Complex CI/CD pipelines (not needed for manual deployment)
- ❌ Automated testing gates (run tests manually when needed)
- ❌ GitHub Actions workflows (unless you really want them)
- ❌ Complex branch protection (optional, can add later)

### What We ARE Doing

- ✅ Simple two-branch structure (`develop` for staging, `main` for production)
- ✅ Secrets checking (critical for security)
- ✅ Deployment scripts (make deployment easy)
- ✅ Clear workflow documentation

---

## Backward Compatibility & API Versioning

### The Problem

When you deploy a new backend version:
- ✅ New iOS app version works with new backend
- ⚠️ Old iOS app versions still in use by users
- ❌ Old app versions may break if backend changes

**You cannot force users to update the app immediately.**

### Reality Check: Keep It Simple

**For early-stage apps with frequent releases:**

1. **Don't maintain old iOS versions locally** - Too complex
2. **Use semantic versioning** - Align frontend and backend versions
3. **Enforce minimum app version** - Force updates for breaking changes
4. **Test current version only** - Don't test old versions

**This is simpler and more practical than maintaining multiple versions.**

### Recommended Approach: Weekly Releases + Support 1 Version Back

**Practical strategy for weekly production updates:**

#### Strategy Overview

- **Weekly releases**: Deploy frontend + backend together every week
- **Support 1 version back**: Current version (1.2.0) + previous version (1.1.0)
- **Testing**: Test production frontend with staging backend before production deploy

#### Example Timeline

```
Week 1: Release 1.1.0 (frontend + backend)
Week 2: Release 1.2.0 (frontend + backend)
        - Backend 1.2.0 supports frontend 1.1.0 AND 1.2.0
        - Users on 1.1.0 can still use the app
Week 3: Release 1.3.0
        - Backend 1.3.0 supports frontend 1.2.0 AND 1.3.0
        - Drop support for 1.1.0 (users must update)
```

#### Backend Version Support Logic

```sql
-- In RPC functions, check if version is supported
CREATE OR REPLACE FUNCTION rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_apps_to_limit jsonb,
  p_app_version text DEFAULT '1.0.0'
)
RETURNS json AS $$
DECLARE
  v_current_backend_version text := '1.2.0';
  v_supported_versions text[] := ARRAY['1.1.0', '1.2.0'];  -- Current + 1 back
  v_min_supported_version text := '1.1.0';
BEGIN
  -- Check if app version is supported
  IF p_app_version < v_min_supported_version THEN
    RAISE EXCEPTION 'App version % is too old. Please update to version % or later from the App Store.', 
      p_app_version, v_min_supported_version;
  END IF;
  
  -- Version-specific logic (if needed)
  IF p_app_version = '1.1.0' THEN
    -- Old format logic
  ELSIF p_app_version >= '1.2.0' THEN
    -- New format logic
  END IF;
  
  -- Normal logic here
  ...
END;
$$;
```

---

### Testing Production Frontend with Staging Backend

**The Challenge:**
- Production frontend (1.1.0) is built in RELEASE mode → connects to production backend
- Staging backend (1.2.0) is where you want to test
- How to test production frontend with staging backend?

**Solution: Environment Override**

#### Option 1: Build Configuration Override (Recommended)

Add a way to override environment in RELEASE builds:

```swift
// Config.swift
struct SupabaseConfig {
    #if DEBUG
        static let current: Environment = .staging
    #else
        // RELEASE mode - normally production
        static let current: Environment = {
            // Check for override flag (set via Xcode scheme or environment variable)
            if ProcessInfo.processInfo.environment["USE_STAGING"] == "true" {
                return .staging  // Override to staging
            }
            return .production  // Default to production
        }()
    #endif
}
```

**How to use:**
1. In Xcode, create a new Scheme: "Release (Staging)"
2. Edit Scheme → Run → Arguments → Environment Variables
3. Add: `USE_STAGING = true`
4. Build Archive with this scheme
5. Install on device → connects to staging backend

#### Option 2: TestFlight Staging Build

Create a separate TestFlight build that points to staging:

```swift
// Config.swift
struct SupabaseConfig {
    #if DEBUG
        static let current: Environment = .staging
    #else
        // Check for staging TestFlight build
        static let current: Environment = {
            // Use a different bundle ID or build number range for staging TestFlight
            if Bundle.main.bundleIdentifier?.contains("staging") == true {
                return .staging
            }
            return .production
        }()
    #endif
}
```

**How to use:**
1. Create separate Xcode target: "PayAttentionClub Staging"
2. Different bundle ID: `com.payattentionclub.staging`
3. Archive and upload to TestFlight
4. Test with staging backend
5. When ready, use production target for App Store

#### Option 3: Manual Testing Script (Simplest)

For quick testing, temporarily modify `Config.swift`:

```swift
// Temporarily override for testing
static let current: Environment = .staging  // ← Change this
```

Then:
1. Build Archive
2. Install on device
3. Test with staging backend
4. Revert change before App Store submission

**⚠️ Remember to revert before submitting to App Store!**

---

### Weekly Release Workflow

#### Step 1: Develop on Staging (Monday-Wednesday)

```bash
# Work on new features
git checkout develop
git checkout -b feat/new-feature

# Deploy to staging
./scripts/deploy_to_staging.sh

# Test in Xcode (DEBUG mode = staging)
```

#### Step 2: Test Production Frontend with Staging Backend (Thursday)

```bash
# 1. Build production frontend (1.1.0) with staging override
#    - Use Option 1: Create "Release (Staging)" scheme
#    - Or Option 3: Temporarily change Config.swift

# 2. Install on device
# 3. Test all critical flows
# 4. Verify compatibility

# 5. Revert staging override
```

#### Step 3: Deploy to Production (Friday)

```bash
# 1. Merge to main
git checkout main && git merge develop

# 2. Update version numbers
#    - iOS: 1.2.0
#    - Backend: Update supported_versions array

# 3. Deploy backend
./scripts/deploy_to_production.sh

# 4. Archive iOS (RELEASE mode = production)
# 5. Upload to App Store Connect
# 6. Submit for review
```

#### Step 4: Monitor (Weekend)

- Check if old version (1.1.0) still works
- Monitor error logs for version issues
- Prepare next week's release

---

### Version Support Matrix

| Backend Version | Supports Frontend Versions | Notes |
|----------------|---------------------------|-------|
| 1.1.0 | 1.0.0, 1.1.0 | Initial release |
| 1.2.0 | 1.1.0, 1.2.0 | Supports 1 version back |
| 1.3.0 | 1.2.0, 1.3.0 | Drops 1.1.0 support |
| 1.4.0 | 1.3.0, 1.4.0 | Drops 1.2.0 support |

**Rule:** Always support current version + 1 version back.

---

### Alternative: Semantic Versioning + Minimum Version (Simpler)

**If weekly releases + 1 version back is too complex, use minimum version:**

#### 1. Use Semantic Versioning

```
Frontend: 1.2.0
Backend:  1.2.0
```

- Major version (1.x.x) = Breaking changes (force update)
- Minor version (x.2.x) = New features (backward compatible)
- Patch version (x.x.0) = Bug fixes (backward compatible)

#### 2. Enforce Minimum App Version

```sql
-- In RPC functions, check app version
CREATE OR REPLACE FUNCTION rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_apps_to_limit jsonb,
  p_app_version text DEFAULT '1.0.0'  -- App sends its version
)
RETURNS json AS $$
DECLARE
  v_min_version text := '1.2.0';  -- Minimum required version
BEGIN
  -- Force update for breaking changes
  IF p_app_version < v_min_version THEN
    RAISE EXCEPTION 'App version too old. Please update from App Store. Required: %', v_min_version;
  END IF;
  
  -- Normal logic here
  ...
END;
$$;
```

#### 3. Version Your Backend

Store backend version in database:

```sql
-- Track backend version
CREATE TABLE IF NOT EXISTS _internal_config (
  key text PRIMARY KEY,
  value text,
  updated_at timestamptz DEFAULT NOW()
);

-- Set backend version
INSERT INTO _internal_config (key, value) 
VALUES ('backend_version', '1.2.0')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

#### 4. Simple Deployment Flow

```bash
# 1. Update version numbers (both frontend and backend)
#    - iOS: Info.plist CFBundleShortVersionString = "1.2.0"
#    - Backend: _internal_config.backend_version = "1.2.0"

# 2. Deploy backend
./scripts/deploy_to_production.sh

# 3. Release iOS app
#    - Archive in Xcode
#    - Upload to App Store Connect
#    - Set minimum version requirement in App Store (if needed)
```

**Result:**
- Old apps get error message: "Please update from App Store"
- Users update to new version
- No need to maintain old versions locally

---

### Alternative: Backward Compatible Changes (More Complex)

**Only use this if you need to support old versions for extended periods.**

**Always make backend changes backward compatible:**

#### ✅ Safe Changes (No Breaking)
- **Add new RPC functions** - Old apps ignore them
- **Add new optional parameters** - Old apps work without them
- **Add new database columns** - Old apps don't query them
- **Add new Edge Functions** - Old apps don't call them

#### ⚠️ Risky Changes (May Break)
- **Remove RPC functions** - Old apps will get 404 errors
- **Remove required parameters** - Old apps will get validation errors
- **Change response format** - Old apps may fail to parse
- **Change database schema** - Old apps may query wrong columns

### Best Practices (For Backward Compatible Approach)

#### 1. **Additive Changes Only**
```sql
-- ✅ GOOD: Add new optional parameter
CREATE OR REPLACE FUNCTION rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_apps_to_limit jsonb,
  p_new_optional_param integer DEFAULT NULL  -- New, optional
)

-- ❌ BAD: Remove required parameter
CREATE OR REPLACE FUNCTION rpc_create_commitment(
  p_deadline_date date,
  -- p_limit_minutes integer,  -- REMOVED - breaks old apps!
  p_penalty_per_minute_cents integer
)
```

#### 2. **Version Your RPC Functions (If Needed)**
```sql
-- Old version (keep for backward compatibility)
CREATE OR REPLACE FUNCTION rpc_create_commitment_v1(...)

-- New version (new apps use this)
CREATE OR REPLACE FUNCTION rpc_create_commitment_v2(...)
```

#### 3. **Gradual Migration Strategy**

**Phase 1: Deploy Backend (Backward Compatible)**
```bash
# Deploy new backend that supports both old and new formats
./scripts/deploy_to_production.sh
# Old apps continue working
# New app version not released yet
```

**Phase 2: Release New iOS App**
```
# Submit new iOS version to App Store
# Users gradually update over days/weeks
# Both old and new app versions work with backend
```

**Phase 3: Deprecate Old Format (After Most Users Updated)**
```sql
-- After 90%+ users updated, you can:
-- 1. Log warnings for old format usage
-- 2. Eventually remove old format support
-- 3. Force minimum app version (if critical)
```

#### 4. **Handle Breaking Changes Carefully**

If you MUST make a breaking change:

**Option A: Dual Support Period**
```sql
-- Support both old and new format for 3-6 months
CREATE OR REPLACE FUNCTION rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,  -- Old format
  p_limit_hours integer DEFAULT NULL  -- New format
)
RETURNS json AS $$
BEGIN
  -- Use new format if provided, fallback to old
  IF p_limit_hours IS NOT NULL THEN
    -- New logic
  ELSE
    -- Old logic (convert minutes to hours)
  END IF;
END;
$$;
```

**Option B: Force Minimum App Version**
```sql
-- Check app version in RPC
CREATE OR REPLACE FUNCTION rpc_create_commitment(
  p_deadline_date date,
  p_app_version text DEFAULT '1.0.0'
)
RETURNS json AS $$
BEGIN
  -- Require minimum version for new features
  IF p_app_version < '2.0.0' THEN
    RAISE EXCEPTION 'App version too old. Please update from App Store.';
  END IF;
  -- New logic
END;
$$;
```

### Real-World Example: Authorization Fee Fix

When we fixed the authorization fee calculation:

1. **Backend Change**: New `calculate_max_charge_cents()` function
2. **Backward Compatible**: Old `rpc_create_commitment` still works
3. **New Feature**: Added `rpc_preview_max_charge` (new apps use this)
4. **Old Apps**: Still work, just don't get the preview feature
5. **New Apps**: Get better UX with preview

**Result**: No breaking changes, gradual improvement.

### Monitoring Old App Versions

Track which app versions are in use:

```sql
-- Add app_version to requests (optional)
CREATE TABLE api_requests (
  user_id uuid,
  app_version text,
  endpoint text,
  created_at timestamptz
);

-- Log in RPC functions
INSERT INTO api_requests (user_id, app_version, endpoint)
VALUES (auth.uid(), current_setting('app.version', true), 'rpc_create_commitment');
```

Then query:
```sql
SELECT app_version, COUNT(*) 
FROM api_requests 
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY app_version;
```

### Comparison: Classic Backend Approach

**How classic backends handle this:**

Most backends use **API versioning**:
```
/api/v1/create_commitment
/api/v2/create_commitment
```

**Why this works:**
- Old apps call `/v1/` endpoints (kept running)
- New apps call `/v2/` endpoints (new features)
- Backend maintains both versions
- Eventually deprecate `/v1/` after users migrate

**For Supabase RPC:**
- You can version function names: `rpc_create_commitment_v1`, `rpc_create_commitment_v2`
- Or use minimum version enforcement (simpler)

---

### Recommended: Minimum Version Strategy

**For frequent releases (weekly), use minimum version enforcement:**

#### Pros:
- ✅ Simple - no need to maintain old versions
- ✅ Fast iteration - deploy breaking changes immediately
- ✅ Clear - users know they need to update
- ✅ Less testing burden - only test current version

#### Cons:
- ⚠️ Users must update (but that's usually fine for early-stage apps)
- ⚠️ Some users may be temporarily blocked

#### Implementation:

1. **App sends version** in RPC calls (add to all RPCs)
2. **Backend checks version** against minimum required
3. **Return clear error** if version too old
4. **Update minimum** when you deploy breaking changes

**Example:**
```swift
// iOS: Send app version in RPC calls
let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
let params = CreateCommitmentParams(
    deadlineDate: deadline,
    limitMinutes: limit,
    appVersion: appVersion  // ← Add this
)
```

```sql
-- Backend: Check version
IF p_app_version < '1.2.0' THEN
  RAISE EXCEPTION 'Please update to version 1.2.0 or later from the App Store';
END IF;
```

---

### Deployment Checklist (Minimum Version Strategy)

Before deploying backend changes:

- [ ] **Breaking change?** → Update minimum version in backend
- [ ] **Update iOS version** → Bump version in Info.plist
- [ ] **Deploy backend** → New minimum version enforced
- [ ] **Release iOS app** → Users update, get new features
- [ ] **Monitor** → Check if users are blocked (should be minimal)

**That's it. Simple and effective.**

---

## Related Documentation

- `ARCHITECTURE.md` - System architecture
- `docs/AUTHORIZATION_FEE_FIX.md` - Recent auth calculation fix
- `docs/PHASE7_VERIFICATION.md` - Environment verification checklist


