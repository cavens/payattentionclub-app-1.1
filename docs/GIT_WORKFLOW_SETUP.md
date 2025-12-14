# Git Workflow Setup Guide

This guide explains how to set up and use the Git workflow with staging and production environments.

## Overview

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

## Step 1: Create the Branch Structure

### 1.1 Create `develop` Branch (Staging)

```bash
# Make sure you're on main and it's up to date
git checkout main
git pull origin main

# Create develop branch from main
git checkout -b develop

# Push develop to remote
git push -u origin develop
```

### 1.2 Set Default Branch Protection (Optional but Recommended)

On GitHub:
1. Go to Settings → Branches
2. Add rule for `main`:
   - ✅ Require pull request reviews before merging
   - ✅ Require status checks to pass
   - ✅ Include administrators
3. Add rule for `develop`:
   - ✅ Require pull request reviews before merging (optional, less strict)
   - ✅ Include administrators

---

## Step 2: Daily Development Workflow

### 2.1 Start a New Feature

```bash
# Start from develop (staging branch)
git checkout develop
git pull origin develop

# Create feature branch
git checkout -b feat/my-feature-name

# Make your changes...
# - Edit Swift files
# - Edit SQL/RPC files
# - Edit Edge Functions
```

### 2.2 Test Locally

```bash
# Run backend tests
./scripts/run_backend_tests.sh staging

# Build iOS app in Xcode (DEBUG mode = staging)
# Product → Run (⌘R)
```

### 2.3 Deploy to Staging

```bash
# Deploy SQL/RPC functions to staging
./scripts/deploy_to_staging.sh

# Test in iOS app (connects to staging automatically in DEBUG mode)
```

### 2.4 Commit Changes

```bash
# ⚠️ IMPORTANT: Check for secrets FIRST!
./scripts/check_secrets.sh

# If check passes, stage and commit
git add -A
git commit -m "feat: description of your changes"

# Push feature branch
git push origin feat/my-feature-name
```

### 2.5 Merge to Develop (Staging)

```bash
# Option A: Create Pull Request on GitHub (recommended)
# 1. Go to GitHub → Create PR: feat/my-feature-name → develop
# 2. Review changes
# 3. Merge PR

# Option B: Merge locally (if solo dev)
git checkout develop
git pull origin develop
git merge feat/my-feature-name
git push origin develop
```

### 2.6 Deploy to Staging Environment

After merging to `develop`:

```bash
# Deploy latest code to staging Supabase
./scripts/deploy_to_staging.sh

# Test thoroughly in staging
# - iOS app in DEBUG mode
# - Backend tests: ./scripts/run_backend_tests.sh staging
```

---

## Step 3: Production Release Workflow

### 3.1 Merge Develop → Main (Production)

**Only when staging is fully tested and ready:**

```bash
# Make sure develop is up to date
git checkout develop
git pull origin develop

# Switch to main
git checkout main
git pull origin main

# Merge develop into main
git merge develop

# Push to main
git push origin main
```

**Or use GitHub PR:**
1. Create PR: `develop` → `main`
2. Review all changes
3. Ensure staging tests passed
4. Merge PR

### 3.2 Deploy to Production

```bash
# ⚠️ CRITICAL: Deploy SQL/RPC to production
./scripts/deploy_to_production.sh

# Deploy Edge Functions manually in Supabase Dashboard
# (See DEPLOYMENT_WORKFLOW.md for details)

# Verify production works
# - Check Supabase logs
# - Test critical flows
```

### 3.3 Tag Release (Optional)

```bash
# Tag the release
git tag -a v1.2.0 -m "Release 1.2.0: description"
git push origin v1.2.0
```

---

## Step 4: Hotfix Workflow (Urgent Production Fix)

For urgent production bugs:

```bash
# Start from main (production)
git checkout main
git pull origin main

# Create hotfix branch
git checkout -b hotfix/critical-bug-fix

# Make the fix
# ... edit files ...

# Test locally
./scripts/run_backend_tests.sh production  # ⚠️ Careful!

# Commit
./scripts/check_secrets.sh  # ⚠️ Always check secrets!
git add -A
git commit -m "hotfix: critical bug fix"

# Merge to main AND develop
git checkout main
git merge hotfix/critical-bug-fix
git push origin main

git checkout develop
git merge hotfix/critical-bug-fix
git push origin develop

# Deploy to production immediately
./scripts/deploy_to_production.sh
```

---

## Step 5: Pre-Push Safety Checks

### 5.1 Create Secrets Check Script

Create `scripts/check_secrets.sh`:

```bash
#!/bin/bash
# Check for secrets in staged files before push

set -e

echo "🔍 Checking for secrets in staged files..."

# Patterns to detect
PATTERNS=(
    "sk_live_[a-zA-Z0-9]{24,}"      # Stripe live key
    "sk_test_[a-zA-Z0-9]{24,}"      # Stripe test key
    "whsec_[a-zA-Z0-9]{32,}"        # Stripe webhook secret
    "eyJ[A-Za-z0-9_-]{100,}"        # JWT tokens (service role keys)
    "sbp_[a-zA-Z0-9]{32,}"          # Supabase project tokens
)

# Get staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo "✅ No staged files to check"
    exit 0
fi

FOUND_SECRETS=false

for file in $STAGED_FILES; do
    # Skip .env files (they're gitignored anyway)
    if [[ "$file" == *".env"* ]]; then
        continue
    fi
    
    for pattern in "${PATTERNS[@]}"; do
        if git diff --cached "$file" | grep -qE "$pattern"; then
            echo "❌ SECRET DETECTED in $file:"
            echo "   Pattern: $pattern"
            FOUND_SECRETS=true
        fi
    done
done

if [ "$FOUND_SECRETS" = true ]; then
    echo ""
    echo "🚨 BLOCKED: Secrets detected in staged files!"
    echo "   Remove secrets before pushing to remote."
    echo "   See docs/KNOWN_ISSUES.md for details."
    exit 1
fi

echo "✅ No secrets detected"
exit 0
```

Make it executable:
```bash
chmod +x scripts/check_secrets.sh
```

### 5.2 Set Up Git Pre-Push Hook

Create `.git/hooks/pre-push`:

```bash
#!/bin/bash
# Pre-push hook: Run secrets check before pushing

echo "🔍 Running pre-push checks..."

# Run secrets check
./scripts/check_secrets.sh

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Push blocked: Secrets detected"
    exit 1
fi

echo "✅ Pre-push checks passed"
exit 0
```

Make it executable:
```bash
chmod +x .git/hooks/pre-push
```

**Note**: Git hooks are not tracked in git. You'll need to recreate this on each machine or use a tool like [husky](https://github.com/typicode/husky) for JavaScript projects (not applicable here, but the concept is the same).

---

## Step 6: Environment Mapping

| Git Branch | Supabase Environment | iOS Build Mode | When to Use |
|-----------|---------------------|----------------|-------------|
| `feat/*` | Local dev only | DEBUG | Feature development |
| `develop` | **Staging** | DEBUG | Integration testing |
| `main` | **Production** | RELEASE | Live users |

### iOS Environment Selection

The iOS app automatically selects the environment based on build mode:

```swift
// Config.swift
#if DEBUG
    static let current: Environment = .staging  // ← develop branch
#else
    static let current: Environment = .production  // ← main branch
#endif
```

**So:**
- Building in Xcode (⌘R) = DEBUG mode = Staging
- Archiving for App Store = RELEASE mode = Production

---

## Quick Reference

### Daily Development
```bash
git checkout develop
git pull
git checkout -b feat/my-feature
# ... make changes ...
./scripts/check_secrets.sh
git add -A && git commit -m "feat: ..."
git push origin feat/my-feature
# Create PR: feat/my-feature → develop
```

### Release to Production
```bash
# After staging is tested
git checkout main
git pull
git merge develop
git push origin main
./scripts/deploy_to_production.sh
```

### Hotfix
```bash
git checkout main
git checkout -b hotfix/fix-name
# ... fix ...
./scripts/check_secrets.sh
git add -A && git commit -m "hotfix: ..."
git checkout main && git merge hotfix/fix-name
git checkout develop && git merge hotfix/fix-name
git push origin main develop
./scripts/deploy_to_production.sh
```

---

## Troubleshooting

### "Secrets detected" but they're in .env file
- `.env` should be in `.gitignore` (it is)
- If secrets are in other files, remove them and use environment variables instead

### Can't push because pre-push hook failed
- Review the secrets check output
- Remove secrets from staged files
- Or temporarily bypass: `git push --no-verify` (⚠️ NOT recommended)

### Accidentally committed secrets
1. **Rotate the secret immediately** in Supabase/Stripe
2. Remove from git history: `./scripts/remove_secrets_from_history.sh`
3. Force push: `git push --force` (coordinate with team if applicable)

---

## Next Steps

1. ✅ Create `develop` branch
2. ✅ Set up `scripts/check_secrets.sh`
3. ✅ Set up `.git/hooks/pre-push`
4. ⬜ Test the workflow with a small change
5. ⬜ Set up GitHub Actions CI/CD (future)

See `DEPLOYMENT_WORKFLOW.md` for the full deployment process.

