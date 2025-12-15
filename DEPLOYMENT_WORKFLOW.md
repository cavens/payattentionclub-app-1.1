# Unified Deployment Workflow

This document describes the complete development, testing, and deployment workflow for both the iOS frontend and Supabase backend.

---

## Environments

| Environment | Purpose | Supabase Project | iOS Build Mode |
|-------------|---------|------------------|----------------|
| **Staging** | Testing before production | `auqujbppoytkeqdsgrbl` | DEBUG mode |
| **Production** | Live users | `whdftvcrtrsnefhprebj` | RELEASE mode |

---

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

---

## Complete Deployment Workflow

### Phase 1: Development (Local)

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

**What you're working on:**
- Frontend: Swift code changes
- Backend: SQL/RPC functions, Edge Functions
- Both: Tested locally first

---

### Phase 2: Deploy to Staging

#### 2.1 Deploy Backend to Staging

```bash
# Deploy SQL/RPC functions to staging
./scripts/deploy_to_staging.sh
```

**What this does:**
- Reads SQL files from `supabase/remote_rpcs/*.sql`
- Sources staging credentials from `.env`
- Calls Supabase API: `POST /rest/v1/rpc/rpc_execute_sql`
- Executes SQL in staging database

#### 2.2 Deploy Edge Functions to Staging (Manual)

1. Go to Supabase Dashboard → Edge Functions
2. For each function (`rapid-service`, `billing-status`, `weekly-close`, `bright-service`):
   - Select the function
   - Copy-paste new code from `supabase/functions/[name]/index.ts`
   - Click Deploy

#### 2.3 Test Frontend on Staging

```bash
# Build iOS in DEBUG mode (Xcode)
# - DEBUG mode automatically connects to staging
# - Product → Run (⌘R) in Xcode
# - Test on device/simulator
```

**What happens:**
- Xcode builds in DEBUG mode
- `Config.swift` selects `.staging` environment
- App connects to staging Supabase
- You test all features

---

### Phase 3: Testing & Validation

#### 3.1 Run Test Harness

```bash
# Run backend tests against staging
./scripts/run_backend_tests.sh staging

# Run iOS unit tests (in Xcode)
# Product → Test (⌘U)
```

**Why:** Catch bugs before committing to git.

#### 3.2 Pre-Commit Safety Check

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

**Critical:** Never commit secrets to git!

---

### Phase 4: Commit & Merge to Develop

```bash
# Only after staging tests pass AND secrets check passes!
git add -A
git commit -m "feat: description of changes"
git push origin feat/my-feature

# Create Pull Request: feat/my-feature → develop (staging)
# Or merge directly for solo dev:
git checkout develop
git pull origin develop
git merge feat/my-feature
git push origin develop
```

**Current state:**
- ✅ Code in `develop` branch (staging)
- ✅ Backend deployed to staging Supabase
- ✅ Frontend tested on staging
- ✅ All tests passing

---

### Phase 5: Test Production Frontend with Staging Backend ⚠️ MANDATORY

```bash
# ⚠️ CRITICAL: Test current production frontend with new staging backend
# This ensures backward compatibility before deploying to production

./scripts/test_production_frontend_with_staging.sh
```

**What this does:**
1. Builds current production iOS version (e.g., 1.1.0) with staging override
2. Connects it to staging backend (using `USE_STAGING=true` environment variable)
3. Provides checklist of critical flows to test manually:
   - Sign in
   - Create commitment
   - View authorization amount
   - Complete payment flow
   - Check billing status
4. Blocks deployment until tests pass

**Why this is MANDATORY:**
- Ensures old app versions won't break when you deploy new backend
- Catches backward compatibility issues early
- Prevents production outages

**How it works:**
- Create Xcode scheme "Release (Staging)"
- Set environment variable: `USE_STAGING = true`
- Build Archive with this scheme
- Install on device → connects to staging backend
- Test all critical flows

---

### Phase 6: Merge to Main (Production Git)

```bash
# Only after production frontend compatibility test passes!
git checkout main
git pull origin main
git merge develop
git push origin main
```

**What happens:**
- Code moves from `develop` branch to `main` branch
- This is **ONLY version control** - nothing deploys yet
- Production Supabase still running old code
- Production iOS app still running old code

**Current state:**
- ✅ Git `main` branch has new code
- ❌ Production Supabase still has old code
- ❌ Production iOS app not yet released

---

### Phase 7: Deploy Backend to Production

#### 7.1 Deploy SQL/RPC Functions

```bash
# Deploy SQL/RPC functions to production
./scripts/deploy_to_production.sh
```

**What this script does:**
1. Reads SQL files from local git repo (`supabase/remote_rpcs/*.sql`)
2. Sources production credentials from `.env`
3. Calls Supabase API directly: `POST /rest/v1/rpc/rpc_execute_sql`
4. Executes SQL in production database

**Note:** This is a **shell script**, not a Deno script. It uses `curl` to call Supabase REST API.

**Result:**
- ✅ Production Supabase now running new backend code
- ✅ New RPC functions available
- ✅ Old app versions still work (if backward compatible)

#### 7.2 Deploy Edge Functions (Manual)

Edge Functions require manual deployment in Supabase Dashboard:

1. Go to Supabase Dashboard → Edge Functions
2. For each function (`rapid-service`, `billing-status`, `weekly-close`, `bright-service`):
   - Select the function
   - Copy-paste new code from `supabase/functions/[name]/index.ts`
   - Click Deploy

**Why manual:** Supabase doesn't have CLI deployment for Edge Functions (or it's complex to set up).

#### 7.3 Verify Backend Deployment

```bash
# Test that new functions work
curl -X POST "${PRODUCTION_SUPABASE_URL}/rest/v1/rpc/rpc_preview_max_charge" \
  -H "Authorization: Bearer ${PRODUCTION_SUPABASE_SECRET_KEY}" \
  -d '{"p_deadline_date": "2024-12-16", ...}'

# Check Supabase Dashboard → Database → Functions
# Verify new functions exist
```

**Current state:**
- ✅ Production backend deployed
- ✅ Backend verified working
- ⏳ Production iOS app not yet released (can deploy separately)

---

### Phase 8: Deploy Frontend to Production (iOS)

**Important:** Frontend deployment is **separate** from backend. You can deploy them independently.

#### 8.1 Build Archive in Xcode

1. **Open Xcode**
2. **Select RELEASE scheme** (not DEBUG)
   - Scheme: `payattentionclub-app-1.1`
   - Configuration: Release
3. **Product → Archive**
   - Xcode builds optimized binary
   - Creates `.xcarchive` file
   - **RELEASE mode = connects to production backend**

**What happens:**
- Xcode compiles Swift code
- Links with production Supabase URLs (from `Config.swift`)
- Creates optimized binary (smaller, faster)
- Signs with your distribution certificate

**Note:** Make sure production backend is deployed first (Phase 7)!

#### 8.2 Distribute Archive

1. **Xcode Organizer opens** (shows your archive)
2. **Click "Distribute App"**
3. **Choose distribution method:**
   - **App Store Connect** (for App Store release)
   - **TestFlight** (for beta testing)
   - **Ad Hoc** (for specific devices)
4. **Follow prompts:**
   - Select distribution certificate
   - Upload symbols (for crash reports)
   - Upload to App Store Connect

**What happens:**
- Xcode creates `.ipa` file (iOS app package)
- Uploads to App Store Connect via API
- Processing takes 10-30 minutes

#### 8.3 Submit for Review (App Store Connect)

1. **Go to App Store Connect** (web UI)
   - https://appstoreconnect.apple.com
2. **Select your app**
3. **Go to: App Store → Versions**
4. **Select the new version** (uploaded from Xcode)
5. **Fill in:**
   - Version number
   - What's new in this version
   - Screenshots (if needed)
   - App Store description
6. **Submit for Review**

**What happens:**
- Apple reviews your app (1-3 days typically)
- You get notified of approval/rejection
- Once approved, app goes live on App Store

**Current state:**
- ✅ Production backend deployed
- ✅ Production iOS app submitted for review
- ⏳ Waiting for Apple review (1-3 days)

---

### Phase 9: Release Complete

**After Apple approves:**
- ✅ App goes live on App Store
- ✅ Users can download/update
- ✅ Complete deployment cycle finished

**Optional: Tag the release**
```bash
git tag -a v1.2.0 -m "Release 1.2.0"
git push origin v1.2.0
```

---

## Complete Example: Weekly Release

### Scenario: Releasing Version 1.2.0

**Monday-Wednesday: Development**
```bash
git checkout develop
git checkout -b feat/new-feature
# Edit Swift files
# Edit SQL/RPC functions
./scripts/deploy_to_staging.sh  # Deploy backend to staging
# Test in Xcode (DEBUG = staging)
git commit -m "feat: new feature"
git checkout develop && git merge feat/new-feature
git push origin develop
```

**Thursday: Testing**
```bash
# Test on staging
./scripts/run_backend_tests.sh staging
# Product → Test (⌘U) in Xcode

# ⚠️ MANDATORY: Test production frontend with staging backend
./scripts/test_production_frontend_with_staging.sh
# Build production frontend (1.1.0) with staging override
# Test manually - all flows work ✅
```

**Friday: Production Deployment**

**Backend:**
```bash
# 1. Merge to main
git checkout main
git merge develop
git push origin main

# 2. Deploy backend to production
./scripts/deploy_to_production.sh

# 3. Deploy Edge Functions (if changed)
# Manual in Supabase Dashboard

# 4. Verify backend
# Test RPC functions, check logs
```

**Frontend:**
```bash
# 1. Build Archive in Xcode
#    Product → Archive (RELEASE mode)

# 2. Distribute App
#    Upload to App Store Connect

# 3. Submit for Review
#    In App Store Connect web UI
```

**Next Week:**
- Apple reviews app (1-3 days)
- App goes live on App Store
- Users can download/update

---

## Deployment Scripts

### Backend Scripts

**Deploy to Staging:**
```bash
./scripts/deploy_to_staging.sh
```
Deploys all SQL/RPC functions from `supabase/remote_rpcs/` to staging.

**Deploy to Production:**
```bash
./scripts/deploy_to_production.sh
```
Deploys all SQL/RPC functions from `supabase/remote_rpcs/` to production.

**How it works:**
- Shell script (not Deno)
- Reads SQL files from local git repo
- Uses `curl` to call Supabase REST API: `POST /rest/v1/rpc/rpc_execute_sql`
- Sources credentials from `.env` file
- Executes SQL directly in database

**Run Backend Tests:**
```bash
./scripts/run_backend_tests.sh staging      # Test against staging
./scripts/run_backend_tests.sh production   # Test against production (careful!)
```

**Test Production Frontend with Staging Backend:**
```bash
./scripts/test_production_frontend_with_staging.sh
```
**MANDATORY** before deploying backend to production. Tests current production iOS version with new staging backend to ensure backward compatibility.

### Frontend Scripts

**No scripts needed** - Frontend deployment is done manually in Xcode:
1. Product → Archive
2. Distribute App
3. Submit in App Store Connect

---

## Key Concepts

### Git vs Deployment

**Git is for version control, NOT deployment.**

- ✅ Git stores code history and enables collaboration
- ❌ Git does NOT automatically deploy to Supabase
- ❌ Git does NOT automatically build iOS app
- ✅ We deploy directly from local to Supabase using scripts/API calls
- ✅ iOS builds happen locally in Xcode (Archive → App Store Connect)

**Deployment Flow:**
```
Backend: Local Code → Git → Local Script → Supabase (direct API)
Frontend: Local Code → Git → Xcode Archive → App Store Connect
```

### Frontend vs Backend Deployment

| Aspect | Frontend (iOS) | Backend (Supabase) |
|--------|----------------|-------------------|
| **Deployment Method** | Xcode Archive → App Store Connect | Shell script → Supabase API |
| **Time to Deploy** | Minutes (build + upload) | Seconds (API call) |
| **Time to Live** | 1-3 days (Apple review) | Immediate (after deploy) |
| **Can Deploy Separately?** | Yes | Yes |
| **Rollback** | Submit new version | Deploy previous SQL |
| **Manual Steps** | Build, upload, submit | Run script, deploy Edge Functions |

**Key Point:** Frontend and backend can be deployed independently. You don't need to deploy both at the same time.

### iOS Build Modes

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

**For testing production frontend with staging backend:**
```swift
// Config.swift - Add environment variable check
static let current: Environment = {
    if ProcessInfo.processInfo.environment["USE_STAGING"] == "1" {
        return .staging  // Override to staging
    }
    return .production
}()
```

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

### Rollback Backend

```bash
# Revert to previous commit
git checkout HEAD~1 -- supabase/remote_rpcs/[function].sql

# Deploy the old version
./scripts/deploy_to_production.sh
```

**Edge Functions:**
- Go to Supabase Dashboard → Edge Functions
- View deployment history
- Redeploy previous version

### Rollback Frontend

- App Store submissions can't be instantly rolled back
- Submit a new version with the fix
- Or use TestFlight for staged rollouts
- Apple fast-track review (if critical)

---

## Backward Compatibility & API Versioning

### The Problem

When you deploy a new backend version:
- ✅ New iOS app version works with new backend
- ⚠️ Old iOS app versions still in use by users
- ❌ Old app versions may break if backend changes

**You cannot force users to update the app immediately.**

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
            if ProcessInfo.processInfo.environment["USE_STAGING"] == "1" {
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
3. Add: `USE_STAGING = 1`
4. Build Archive with this scheme
5. Install on device → connects to staging backend

#### Option 2: Manual Testing Script (Simplest)

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

### Version Support Matrix

| Backend Version | Supports Frontend Versions | Notes |
|----------------|---------------------------|-------|
| 1.1.0 | 1.0.0, 1.1.0 | Initial release |
| 1.2.0 | 1.1.0, 1.2.0 | Supports 1 version back |
| 1.3.0 | 1.2.0, 1.3.0 | Drops 1.1.0 support |
| 1.4.0 | 1.3.0, 1.4.0 | Drops 1.2.0 support |

**Rule:** Always support current version + 1 version back.

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

## Quick Reference

```bash
# === TYPICAL DEVELOPMENT CYCLE ===

# 1. Start feature from develop (staging branch)
git checkout develop && git pull
git checkout -b feat/my-feature

# 2. Make changes, deploy backend to staging
./scripts/deploy_to_staging.sh

# 3. Test in Xcode (DEBUG mode → staging)
# Build and run on device

# 4. Run tests and check for secrets
./scripts/run_backend_tests.sh staging
./scripts/check_secrets.sh
# Product → Test (⌘U) in Xcode

# 5. Commit and merge to develop
git add -A && git commit -m "feat: my feature"
git push origin feat/my-feature
git checkout develop && git pull
git merge feat/my-feature && git push origin develop
./scripts/deploy_to_staging.sh  # Deploy to staging Supabase

# 6. ⚠️ MANDATORY: Test production frontend with staging backend
./scripts/test_production_frontend_with_staging.sh

# 7. After staging is tested, merge to main (production)
git checkout main && git pull
git merge develop && git push origin main

# 8. Deploy backend to production
./scripts/deploy_to_production.sh
# Deploy Edge Functions manually in Dashboard

# 9. Deploy frontend to production
# Build Archive in Xcode (RELEASE mode)
# Distribute App → App Store Connect
# Submit for Review in App Store Connect

# 10. Verify production works
```

---

## Implementation Plan

### Essential Scripts (Priority)
| Task | Status | Description |
|------|--------|-------------|
| 3.1 | ⬜ | **CRITICAL**: Create `scripts/check_secrets.sh` - scan for exposed secrets |
| 2.1 | ⬜ | Create `scripts/deploy_to_staging.sh` - deploy SQL/RPC to staging |
| 2.2 | ⬜ | Create `scripts/deploy_to_production.sh` - deploy SQL/RPC to production |
| 2.3 | ⬜ | Create `scripts/test_production_frontend_with_staging.sh` - test compatibility |

### Optional Scripts
| Task | Status | Description |
|------|--------|-------------|
| 3.4 | ⬜ | Add git pre-push hook (auto-runs check_secrets.sh) |
| 3.2 | ⬜ | Create `scripts/run_backend_tests.sh` - run tests against staging |

### Branch Setup
| Task | Status | Description |
|------|--------|-------------|
| 1.1 | ⬜ | Create `develop` branch for staging work |
| 1.2 | ⬜ | (Optional) Protect `main` branch on GitHub |

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
- ✅ Clear unified workflow documentation
- ✅ Mandatory compatibility testing before production

---

## Related Documentation

- `ARCHITECTURE.md` - System architecture
- `docs/AUTHORIZATION_FEE_FIX.md` - Recent auth calculation fix
- `docs/PHASE7_VERIFICATION.md` - Environment verification checklist
- `docs/PRODUCTION_BACKEND_DEPLOYMENT.md` - Detailed backend deployment (reference)
- `docs/FRONTEND_DEPLOYMENT_FLOW.md` - Detailed frontend deployment (reference)
