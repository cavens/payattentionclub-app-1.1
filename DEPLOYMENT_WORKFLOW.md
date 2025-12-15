# Deployment Workflow

Complete development, testing, and deployment workflow for iOS frontend and Supabase backend.

---

## Environments

| Environment | Supabase Project | iOS Build Mode |
|-------------|------------------|----------------|
| **Staging** | `auqujbppoytkeqdsgrbl` | DEBUG |
| **Production** | `whdftvcrtrsnefhprebj` | RELEASE |

---

## Git Branching

```
feat/* → develop (staging) → main (production)
```

| Branch | Environment | Purpose |
|--------|-------------|---------|
| `feat/*` | Local | Feature development |
| `develop` | Staging | Integration testing |
| `main` | Production | Live users |

---

## Complete Workflow

### 1. Development

```bash
git checkout develop && git pull
git checkout -b feat/my-feature

# Make changes:
# - Swift files in payattentionclub-app-1.1/
# - SQL/RPC in supabase/remote_rpcs/
# - Edge Functions in supabase/functions/
```

### 2. Deploy to Staging

```bash
# Deploy SQL/RPC functions
./scripts/deploy_to_staging.sh

# Deploy Edge Functions (manual)
# Supabase Dashboard → Edge Functions → Copy-paste code → Deploy

# Test in Xcode (DEBUG mode = staging)
# Product → Run (⌘R)
```

**What happens:**
- Script automatically checks for secrets
- Deploys all SQL files from `supabase/remote_rpcs/`
- Tests in Xcode connect to staging automatically

### 3. Testing & Validation

```bash
# Run backend tests
./supabase/tests/run_backend_tests.sh staging

# Run iOS unit tests (in Xcode)
# Product → Test (⌘U)
```

**Note:** Git hooks automatically run secrets check + tests on `git commit` (see below).

### 4. Commit & Merge to Develop

```bash
git add -A
git commit -m "feat: my feature"  # ← Hooks run automatically
git push origin feat/my-feature

# Merge to develop
git checkout develop && git pull
git merge feat/my-feature && git push origin develop
./scripts/deploy_to_staging.sh  # Deploy to staging
```

### 5. Test Production Frontend with Staging Backend ⚠️ MANDATORY

```bash
./scripts/test_production_frontend_with_staging.sh
```

**Why:** Ensures old app versions won't break when deploying new backend.

**What it does:**
1. Builds current production iOS version with staging override
2. Connects to staging backend
3. Provides checklist of critical flows to test
4. Blocks deployment until tests pass

### 6. Merge to Main

```bash
git checkout main && git pull
git merge develop && git push origin main
```

**Note:** This is Git only - nothing deploys yet.

### 7. Deploy Backend to Production

```bash
# Deploy SQL/RPC functions
./scripts/deploy_to_production.sh  # ← Asks for confirmation

# Deploy Edge Functions (manual)
# Supabase Dashboard → Edge Functions → Copy-paste code → Deploy

# Verify
# Test RPC functions, check logs
```

**What happens:**
- Script checks for secrets automatically
- Verifies you're on `main` branch
- Asks for confirmation (type "DEPLOY")
- Deploys all SQL files to production

### 8. Deploy Frontend to Production (iOS)

1. **Build Archive in Xcode**
   - Select RELEASE scheme
   - Product → Archive

2. **Distribute App**
   - Click "Distribute App"
   - Choose: App Store Connect
   - Upload .ipa file

3. **Submit for Review**
   - Go to App Store Connect
   - Select new version
   - Fill in details
   - Submit for Review

**Timeline:** 1-3 days for Apple review

### 9. Release Complete

After Apple approves:
- ✅ App goes live on App Store
- ✅ Users can download/update

---

## Deployment Scripts

### Backend

```bash
./scripts/deploy_to_staging.sh      # Deploy to staging (auto secrets check)
./scripts/deploy_to_production.sh   # Deploy to production (confirmation required)
./supabase/tests/run_backend_tests.sh staging  # Run backend tests
```

### Frontend

```bash
./scripts/test_production_frontend_with_staging.sh  # Test compatibility
```

**How deployment works:**
- Reads SQL files from `supabase/remote_rpcs/*.sql`
- Uses `curl` to call Supabase API: `POST /rest/v1/rpc/rpc_execute_sql`
- Sources credentials from `.env` file

---

## Git Hooks (Automatic Protection)

### Pre-Commit Hook

**Runs automatically on `git commit`:**
1. Checks for secrets → Blocks if found
2. Runs backend tests → Blocks if tests fail
3. Allows commit if both pass

**Bypass (emergencies only):**
```bash
git commit --no-verify -m "emergency fix"
```

### Pre-Push Hook

**Runs automatically on `git push`:**
1. Checks for secrets → Blocks if found

**Bypass (emergencies only):**
```bash
git push --no-verify
```

---

## Key Concepts

### Git vs Deployment

- **Git** = Version control (stores code history)
- **Deployment** = Actual deployment (separate step)

**Flow:**
```
Code → Git → Deployment Script → Supabase (backend)
Code → Git → Xcode Archive → App Store Connect (frontend)
```

### Frontend vs Backend

| Aspect | Frontend (iOS) | Backend (Supabase) |
|--------|----------------|-------------------|
| **Deploy Method** | Xcode Archive | Shell script |
| **Time to Live** | 1-3 days (review) | Immediate |
| **Can Deploy Separately?** | Yes | Yes |

### iOS Build Modes

- **DEBUG** → Staging (Xcode → Run)
- **RELEASE** → Production (Xcode → Archive)

Environment selected automatically in `Config.swift`:
```swift
#if DEBUG
    static let current: Environment = .staging
#else
    static let current: Environment = .production
#endif
```

---

## Secrets Safety

### Automatic Protection

✅ **Git hooks** check before commit/push  
✅ **Deployment scripts** check before deploying  
✅ **GitHub** also scans (push protection)

### What Gets Scanned

- Stripe keys (`sk_live_*`, `sk_test_*`)
- Webhook secrets (`whsec_*`)
- JWT tokens (service role keys)
- Supabase project tokens

### Files That Should NEVER Contain Secrets

- `*.swift`, `*.sql`, `*.ts`, `*.md`, `*.sh`

### Files That CAN Contain Secrets (gitignored)

- `.env`, `*.p8`

---

## Backward Compatibility

### Strategy: Support 1 Version Back

- Current version (1.2.0) + previous version (1.1.0)
- Test production frontend with staging backend before deploying
- Drop support for older versions gradually

### Testing Production Frontend with Staging Backend

**Option 1: Build Configuration Override (Recommended)**

1. Create Xcode scheme: "Release (Staging)"
2. Edit Scheme → Run → Arguments → Environment Variables
3. Add: `USE_STAGING = 1`
4. Build Archive with this scheme
5. Install on device → connects to staging

**Option 2: Temporary Config Override**

```swift
// Config.swift - Temporarily change
static let current: Environment = .staging  // ← Change this
// Remember to revert before App Store submission!
```

---

## Rollback

### Backend

```bash
# Revert to previous commit
git checkout HEAD~1 -- supabase/remote_rpcs/[function].sql
./scripts/deploy_to_production.sh
```

**Edge Functions:** Supabase Dashboard → View history → Redeploy previous version

### Frontend

- Submit new version with fix
- Use TestFlight for quick fixes
- Apple fast-track review (if critical)

---

## Quick Reference

```bash
# === TYPICAL DEVELOPMENT CYCLE ===

# 1. Start feature
git checkout develop && git pull
git checkout -b feat/my-feature

# 2. Deploy to staging
./scripts/deploy_to_staging.sh

# 3. Test in Xcode (DEBUG = staging)

# 4. Commit (hooks run automatically)
git add -A && git commit -m "feat: my feature"

# 5. Merge to develop
git checkout develop && git merge feat/my-feature && git push

# 6. Test production frontend with staging backend
./scripts/test_production_frontend_with_staging.sh

# 7. Merge to main
git checkout main && git merge develop && git push

# 8. Deploy to production
./scripts/deploy_to_production.sh

# 9. Deploy frontend (Xcode → Archive → App Store Connect)
```

---

## Implementation Status

### ✅ Complete

- `develop` branch created
- `check_secrets.sh` - Scans for secrets
- `deploy_to_staging.sh` - Deploys to staging (auto secrets check)
- `deploy_to_production.sh` - Deploys to production (confirmation + secrets check)
- Git pre-commit hook - Auto checks secrets + tests
- Git pre-push hook - Auto checks secrets
- All scripts tested and working

### What's Protected

✅ **Secrets**: Checked before commit, push, and deployment  
✅ **Tests**: Run automatically before commit  
✅ **Deployment**: Scripts verify environment and ask for confirmation

---

## Related Documentation

- `ARCHITECTURE.md` - System architecture
- `docs/PRODUCTION_BACKEND_DEPLOYMENT.md` - Detailed backend deployment
- `docs/FRONTEND_DEPLOYMENT_FLOW.md` - Detailed frontend deployment
