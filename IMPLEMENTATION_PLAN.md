# Step-by-Step Implementation Plan

This document provides a concrete, actionable checklist for implementing the deployment workflow defined in `DEPLOYMENT_WORKFLOW.md`.

---

## Current Status

### ✅ Already in Place

| Item | Status | Notes |
|------|--------|-------|
| `test_production_frontend_with_staging.sh` | ✅ Exists | Already implemented |
| `run_all_tests.sh` | ✅ Exists | Runs backend + iOS tests |
| `run_sql_via_api.sh` | ✅ Exists | Can execute SQL via API |
| `deploy_rpc_functions.sh` | ⚠️ Exists but needs update | Uses psql/manual, should use API |

### ❌ Missing

| Item | Status | Priority |
|------|--------|----------|
| `develop` branch | ✅ **COMPLETE** | **CRITICAL** |
| `check_secrets.sh` | ❌ Missing | **CRITICAL** |
| `deploy_to_staging.sh` | ❌ Missing | **CRITICAL** |
| `deploy_to_production.sh` | ❌ Missing | **CRITICAL** |
| `run_backend_tests.sh` | ⚠️ Check | Medium |
| Git pre-push hook | ❌ Missing | Optional |

---

## Implementation Steps

### Phase 1: Git Branch Setup (5 minutes) ⚠️ CRITICAL

**Goal:** Create `develop` branch for staging work.

#### Step 1.1: Create `develop` Branch

```bash
# From main branch
git checkout main
git pull origin main

# Create develop branch from main
git checkout -b develop
git push -u origin develop

# Verify
git branch -a
# Should show: * develop, main, remotes/origin/develop, remotes/origin/main
```

**Status:** ✅ **COMPLETE** - `develop` branch created and pushed to remote

---

### Phase 2: Essential Scripts (30 minutes) ⚠️ CRITICAL

**Goal:** Create deployment and safety scripts.

#### Step 2.1: Create `scripts/check_secrets.sh` ⚠️ CRITICAL

**Purpose:** Scan codebase for exposed secrets before committing.

**What it should do:**
- Scan all tracked files (not .gitignore files)
- Check for common secret patterns:
  - `sk_live_*` (Stripe live keys)
  - `sk_test_*` (Stripe test keys)
  - `whsec_*` (Stripe webhook secrets)
  - `eyJ*` (JWT tokens, long strings)
  - `sbp_*` (Supabase project tokens)
- Exit with error if secrets found
- Print file names and line numbers

**Status:** ⬜ Not started

#### Step 2.2: Create `scripts/deploy_to_staging.sh`

**Purpose:** Deploy SQL/RPC functions to staging Supabase.

**What it should do:**
- **Mandatory safety check:** Run `check_secrets.sh` (BLOCK if secrets found)
- Read all `.sql` files from `supabase/remote_rpcs/`
- Source staging credentials from `.env`
- For each SQL file:
  - Call `run_sql_via_api.sh staging "$(cat file.sql)"`
  - Or directly call Supabase API: `POST /rest/v1/rpc/rpc_execute_sql`
- Report success/failure for each file
- Exit with error if any file fails

**Note:** Can adapt `deploy_rpc_functions.sh` or create new one.

**Status:** ⬜ Not started

#### Step 2.3: Create `scripts/deploy_to_production.sh`

**Purpose:** Deploy SQL/RPC functions to production Supabase.

**What it should do:**
- **Mandatory safety check:** Run `check_secrets.sh` (BLOCK if secrets found)
- Same as `deploy_to_staging.sh` but for production
- **Add safety confirmation prompt** before deploying
- Double-check environment variables
- Report success/failure

**Status:** ⬜ Not started

#### Step 2.4: Create `scripts/run_backend_tests.sh`

**Purpose:** Run backend tests against specified environment.

**What it should do:**
- Accept argument: `staging` or `production`
- Call `supabase/tests/run_backend_tests.sh` with environment
- Exit with error if tests fail

**Note:** ✅ `supabase/tests/run_backend_tests.sh` already exists and accepts environment argument. Just need wrapper.

**Status:** ⬜ Not started

---

### Phase 3: Script Updates (15 minutes)

**Goal:** Update existing scripts to match workflow.

#### Step 3.1: Update `scripts/deploy_rpc_functions.sh` (Optional)

**Decision:** Keep as-is OR replace with new `deploy_to_staging.sh`/`deploy_to_production.sh`.

**Recommendation:** Create new scripts, keep old one as backup.

**Status:** ⬜ Not started

---

### Phase 4: Git Hooks (10 minutes) ⚠️ CRITICAL

**Goal:** Automatically prevent secrets and broken code from reaching GitHub.

#### Step 4.1: Create Pre-Commit Hook

**Purpose:** Automatically run checks before `git commit`.

**What it should do:**
1. Run `./scripts/check_secrets.sh` → Block commit if secrets found
2. Run `./supabase/tests/run_backend_tests.sh staging` → Block commit if tests fail
3. Allow bypass with `--no-verify` flag (for emergencies only)

**File:** `.git/hooks/pre-commit`

**Implementation:**
```bash
#!/bin/bash
# Pre-commit hook: Check secrets and run tests before committing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$PROJECT_ROOT"

# 1. Check for secrets
echo "🔒 Checking for secrets..."
if ! "$PROJECT_ROOT/scripts/check_secrets.sh"; then
    echo ""
    echo "❌ Commit blocked: Secrets found in code"
    echo "   Remove secrets before committing"
    exit 1
fi

# 2. Run backend tests
echo ""
echo "🧪 Running backend tests..."
if ! "$PROJECT_ROOT/supabase/tests/run_backend_tests.sh" staging; then
    echo ""
    echo "❌ Commit blocked: Tests failed"
    echo "   Fix tests before committing"
    exit 1
fi

# 3. All checks passed
echo ""
echo "✅ All checks passed. Proceeding with commit..."
exit 0
```

**Steps:**
1. Create file: `.git/hooks/pre-commit`
2. Paste the code above
3. Make executable: `chmod +x .git/hooks/pre-commit`

**Status:** ⬜ Not started

#### Step 4.2: Create Pre-Push Hook (Optional Backup)

**Purpose:** Extra safety net before `git push`.

**What it should do:**
1. Run `./scripts/check_secrets.sh` → Block push if secrets found
2. Allow bypass with `--no-verify` flag

**File:** `.git/hooks/pre-push`

**Implementation:**
```bash
#!/bin/bash
# Pre-push hook: Check secrets before pushing to GitHub

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$PROJECT_ROOT"

# Check for secrets
echo "🔒 Checking for secrets before push..."
if ! "$PROJECT_ROOT/scripts/check_secrets.sh"; then
    echo ""
    echo "❌ Push blocked: Secrets found in code"
    echo "   Remove secrets before pushing"
    exit 1
fi

echo "✅ Secrets check passed. Proceeding with push..."
exit 0
```

**Steps:**
1. Create file: `.git/hooks/pre-push`
2. Paste the code above
3. Make executable: `chmod +x .git/hooks/pre-push`

**Status:** ⬜ Not started (optional)

---

### Phase 5: Documentation Updates (10 minutes)

**Goal:** Update docs to reflect implementation status.

#### Step 5.1: Update `DEPLOYMENT_WORKFLOW.md`

- Mark completed items in Implementation Plan section
- Update script references if names changed

**Status:** ⬜ Not started

---

## Detailed Implementation

### Step 2.1: Create `scripts/check_secrets.sh`

**File:** `scripts/check_secrets.sh`

**Requirements:**
- Scan all files in git (not .gitignore)
- Check for secret patterns
- Print matches with file:line
- Exit 1 if secrets found, 0 if clean

**Patterns to check:**
```bash
# Stripe keys
sk_live_[a-zA-Z0-9]{24,}
sk_test_[a-zA-Z0-9]{24,}

# Stripe webhook secrets
whsec_[a-zA-Z0-9]{32,}

# JWT tokens (long base64 strings starting with eyJ)
eyJ[A-Za-z0-9_-]{100,}

# Supabase project tokens
sbp_[a-zA-Z0-9]{32,}

# Generic API keys (if they look suspicious)
# But be careful not to flag false positives
```

**Implementation approach:**
- Use `git ls-files` to get tracked files
- Use `grep -E` with patterns
- Exclude binary files
- Exclude `.env` (already gitignored, but double-check)

---

### Step 2.2: Create `scripts/deploy_to_staging.sh`

**File:** `scripts/deploy_to_staging.sh`

**Requirements:**
- Read all `.sql` files from `supabase/remote_rpcs/`
- Source `.env` file
- For each file:
  - Read SQL content
  - Call Supabase API: `POST /rest/v1/rpc/rpc_execute_sql`
  - Use `STAGING_SUPABASE_URL` and `STAGING_SUPABASE_SECRET_KEY`
  - Check response for success
- Print progress for each file
- Exit 1 if any file fails

**Can reuse:** `run_sql_via_api.sh` logic

---

### Step 2.3: Create `scripts/deploy_to_production.sh`

**File:** `scripts/deploy_to_production.sh`

**Requirements:**
- Same as `deploy_to_staging.sh` but for production
- **Add safety checks:**
  - Confirm you're on `main` branch
  - Prompt: "Deploy to PRODUCTION? (yes/no)"
  - Double-check environment variables are production
- Use `PRODUCTION_SUPABASE_URL` and `PRODUCTION_SUPABASE_SECRET_KEY`
- Print warnings in red/yellow

---

### Step 2.4: Create `scripts/run_backend_tests.sh`

**File:** `scripts/run_backend_tests.sh`

**Requirements:**
- Accept argument: `staging` or `production`
- Call existing test script: `supabase/tests/run_backend_tests.sh $ENV`
- Or run Deno tests directly
- Exit with same code as test script

**Check first:** Does `supabase/tests/run_backend_tests.sh` already accept environment argument?

---

## Testing the Implementation

### Test Checklist

After implementing each phase:

#### Phase 1 Test
- [ ] `git branch -a` shows `develop` branch
- [ ] Can checkout `develop` and `main`
- [ ] Both branches exist on remote

#### Phase 2 Test
- [ ] `./scripts/check_secrets.sh` runs without errors
- [ ] `./scripts/check_secrets.sh` detects test secrets (if you add one temporarily)
- [ ] `./scripts/deploy_to_staging.sh` deploys SQL files
- [ ] `./scripts/deploy_to_production.sh` asks for confirmation
- [ ] `./scripts/run_backend_tests.sh staging` runs tests

#### Phase 3 Test
- [ ] Old scripts still work (if kept)
- [ ] New scripts work as expected

#### Phase 4 Test
- [ ] `git push` runs secrets check automatically
- [ ] Secrets check blocks push if secrets found
- [ ] `git push --no-verify` bypasses check

---

## Quick Start: Minimal Implementation

**If you want to get started quickly, implement in this order:**

1. **Phase 1** (5 min): Create `develop` branch
2. **Step 2.1** (10 min): Create `check_secrets.sh` - **CRITICAL for security**
3. **Step 2.2** (10 min): Create `deploy_to_staging.sh`
4. **Step 2.3** (10 min): Create `deploy_to_production.sh`

**Total: ~35 minutes for essential setup**

Then you can:
- Start using the workflow
- Add optional scripts later
- Add git hooks later

---

## Script Naming Convention

**Current scripts:**
- `deploy_rpc_functions.sh` - Old, uses psql/manual
- `test_production_frontend_with_staging.sh` - ✅ Already correct
- `run_all_tests.sh` - ✅ Already correct

**New scripts (recommended):**
- `check_secrets.sh` - ✅ Matches workflow
- `deploy_to_staging.sh` - ✅ Matches workflow
- `deploy_to_production.sh` - ✅ Matches workflow
- `run_backend_tests.sh` - ✅ Matches workflow (wrapper)

**Decision:** Keep old scripts as backup, or remove them?

---

## Next Steps

1. **Review this plan** - Does it match your needs?
2. **Start with Phase 1** - Create `develop` branch
3. **Implement Phase 2** - Essential scripts
4. **Test everything** - Run through workflow once
5. **Update documentation** - Mark items as complete

---

## Questions to Resolve

1. **Keep `deploy_rpc_functions.sh`?** 
   - Option A: Keep as backup
   - Option B: Remove it
   - Option C: Update it to use API method

2. **Git pre-push hook?**
   - Option A: Implement now
   - Option B: Manual check for now
   - Option C: Skip entirely

3. **Backend tests script?**
   - ✅ `supabase/tests/run_backend_tests.sh` already works and accepts environment
   - Just create wrapper script in `scripts/` that calls it

---

## Summary

**Must Have (Critical):**
- ✅ `develop` branch
- ✅ `check_secrets.sh`
- ✅ `deploy_to_staging.sh`
- ✅ `deploy_to_production.sh`

**Nice to Have (Optional):**
- ⚠️ `run_backend_tests.sh` (wrapper)
- ⚠️ Git pre-push hook
- ⚠️ Update old scripts

**Total Time:** ~1 hour for critical items, ~1.5 hours for everything.
