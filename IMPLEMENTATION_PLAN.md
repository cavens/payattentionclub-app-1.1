# Deployment Workflow Implementation Plan

This is a clean, actionable checklist for implementing the deployment workflow.

---

## Overview

**Goal:** Set up a simple, manual deployment workflow with staging and production environments.

**Key Principles:**
- Git = version control only (not automatic deployment)
- Manual deployment from local machine
- Simple two-branch structure (develop → main)
- Mandatory testing before production

---

## Implementation Steps

### Phase 1: Branch Setup ⏱️ 10 minutes

- [ ] **1.1** Create `develop` branch
  ```bash
  git checkout main
  git pull origin main
  git checkout -b develop
  git push -u origin develop
  ```

- [ ] **1.2** (Optional) Set branch protection on GitHub
  - Go to: Settings → Branches
  - Add rule for `main`: Require pull request reviews

---

### Phase 2: Essential Scripts ⏱️ 30 minutes

- [ ] **2.1** Create `scripts/check_secrets.sh`
  - Scan staged files for secrets (sk_live_, eyJ*, whsec_, etc.)
  - Exit with error if secrets found
  - Block commit if secrets detected

- [ ] **2.2** Create `scripts/deploy_to_staging.sh`
  - Deploy all SQL/RPC from `supabase/remote_rpcs/` to staging
  - Use `rpc_execute_sql` or direct API calls
  - Source `.env` for staging credentials

- [ ] **2.3** Create `scripts/deploy_to_production.sh`
  - Deploy all SQL/RPC from `supabase/remote_rpcs/` to production
  - Use `rpc_execute_sql` or direct API calls
  - Source `.env` for production credentials

- [ ] **2.4** Test scripts work
  ```bash
  ./scripts/check_secrets.sh
  ./scripts/deploy_to_staging.sh
  ```

---

### Phase 3: Testing Scripts ⏱️ 15 minutes

- [ ] **3.1** Verify `scripts/test_production_frontend_with_staging.sh` exists
  - ✅ Already created
  - Guides manual testing of production frontend with staging backend

- [ ] **3.2** (Optional) Add git pre-push hook
  - Create `.git/hooks/pre-push`
  - Auto-run `check_secrets.sh` before push
  - Make executable: `chmod +x .git/hooks/pre-push`

---

### Phase 4: iOS Staging Override Setup ⏱️ 15 minutes

- [ ] **4.1** Set up Xcode scheme for staging override
  - Open Xcode
  - Product → Scheme → Manage Schemes
  - Duplicate `payattentionclub-app-1.1` scheme
  - Rename to: `Release (Staging)`
  - Edit scheme → Run → Arguments → Environment Variables
  - Add: `USE_STAGING = true`

- [ ] **4.2** Update `Config.swift` to support override
  ```swift
  static var current: AppEnvironment {
      #if DEBUG
          return .staging
      #else
          // Check for override
          if ProcessInfo.processInfo.environment["USE_STAGING"] == "true" {
              return .staging
          }
          return .production
      #endif
  }
  ```

---

### Phase 5: Documentation ⏱️ 5 minutes

- [ ] **5.1** Review `DEPLOYMENT_WORKFLOW.md`
  - ✅ Already created and updated
  - Contains full workflow documentation

- [ ] **5.2** (Optional) Update `README.md`
  - Add link to `DEPLOYMENT_WORKFLOW.md`
  - Quick reference for deployment

---

## Quick Start: First Deployment

Once implementation is complete, here's your first deployment:

### 1. Develop on Staging
```bash
git checkout develop
git checkout -b feat/my-feature
# ... make changes ...
./scripts/deploy_to_staging.sh
# Test in Xcode (DEBUG mode = staging)
```

### 2. Commit
```bash
./scripts/check_secrets.sh  # ⚠️ Must pass!
git add -A
git commit -m "feat: my feature"
git checkout develop
git merge feat/my-feature
git push origin develop
```

### 3. Test Production Frontend with Staging Backend
```bash
./scripts/test_production_frontend_with_staging.sh
# Follow checklist, test manually
```

### 4. Deploy to Production
```bash
git checkout main
git merge develop
git push origin main
./scripts/deploy_to_production.sh
# Archive iOS in Xcode (RELEASE mode)
# Upload to App Store Connect
```

---

## Priority Order

**Must Have (Critical):**
1. ✅ Branch setup (develop branch)
2. ✅ Secrets check script
3. ✅ Deployment scripts (staging + production)

**Should Have (Important):**
4. ✅ Testing script (production frontend with staging backend)
5. ✅ iOS staging override setup

**Nice to Have (Optional):**
6. Git pre-push hook
7. Branch protection rules
8. README updates

---

## Estimated Time

- **Phase 1:** 10 minutes
- **Phase 2:** 30 minutes
- **Phase 3:** 15 minutes
- **Phase 4:** 15 minutes
- **Phase 5:** 5 minutes

**Total: ~75 minutes** (1.25 hours)

---

## Files to Create

1. `scripts/check_secrets.sh` - Secrets scanning
2. `scripts/deploy_to_staging.sh` - Deploy to staging
3. `scripts/deploy_to_production.sh` - Deploy to production
4. `.git/hooks/pre-push` - (Optional) Auto secrets check

---

## Files Already Created

- ✅ `DEPLOYMENT_WORKFLOW.md` - Full workflow documentation
- ✅ `scripts/test_production_frontend_with_staging.sh` - Testing helper
- ✅ `docs/DEPLOYMENT_EXPLAINED.md` - How deployment works

---

## Next Steps

1. Start with Phase 1 (branch setup) - 10 minutes
2. Then Phase 2 (essential scripts) - 30 minutes
3. Test everything works
4. Proceed with first deployment

Ready to start? Begin with Phase 1!

