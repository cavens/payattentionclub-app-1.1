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

## Implementation Plan

### Phase 1: Branch Strategy
| Task | Status | Description |
|------|--------|-------------|
| 1.1 | ⬜ | Create `develop` branch for staging work |
| 1.2 | ⬜ | Protect `main` branch (production-ready only) |
| 1.3 | ⬜ | Document branching conventions |

### Phase 2: Deployment Scripts
| Task | Status | Description |
|------|--------|-------------|
| 2.1 | ⬜ | Create `scripts/deploy_to_staging.sh` |
| 2.2 | ⬜ | Create `scripts/deploy_to_production.sh` |
| 2.3 | ⬜ | Create `scripts/deploy_edge_functions.sh` |
| 2.4 | ⬜ | Create `scripts/deploy_all.sh` (master script) |

### Phase 3: Pre-Commit Safety Checks
| Task | Status | Description |
|------|--------|-------------|
| 3.1 | ⬜ | Create `scripts/check_secrets.sh` - scan for exposed secrets |
| 3.2 | ⬜ | Create `scripts/test_staging.sh` - run tests against staging |
| 3.3 | ⬜ | Create `scripts/pre_commit_check.sh` - runs secrets check + tests |
| 3.4 | ⬜ | Add git pre-commit hook (auto-runs check_secrets.sh) |

### Phase 4: Documentation
| Task | Status | Description |
|------|--------|-------------|
| 4.1 | ✅ | Create `DEPLOYMENT_WORKFLOW.md` (this file) |
| 4.2 | ⬜ | Create `docs/BRANCHING_STRATEGY.md` |
| 4.3 | ⬜ | Update `README.md` with workflow overview |

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

## Questions to Decide

1. **Branch strategy**: Use `develop` branch or just `main` + feature branches?
2. **Automation level**: Basic scripts, pre-commit hooks, or GitHub Actions?
3. **Edge Functions**: Keep manual or try CLI deployment?
4. **iOS deployment**: Keep separate from this flow?

---

## Related Documentation

- `ARCHITECTURE.md` - System architecture
- `docs/AUTHORIZATION_FEE_FIX.md` - Recent auth calculation fix
- `docs/PHASE7_VERIFICATION.md` - Environment verification checklist


