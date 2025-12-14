# Production Backend Deployment Process

This document explains step-by-step what happens when you deploy the backend to production.

---

## Overview

**Important:** Pushing to Git does NOT deploy to production. Deployment is a separate manual step.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Local Git  │     │   Staging   │     │ Production  │
│  (develop)  │ --> │  Supabase   │ --> │  Supabase   │
└─────────────┘     └─────────────┘     └─────────────┘
     │                    │                    │
     │                    │                    │
     │ 1. Code changes    │                    │
     │ 2. Commit to git    │                    │
     │ 3. Merge to main    │                    │
     │                    │                    │
     │                    │ 4. Test staging    │
     │                    │ 5. Test prod       │
     │                    │    frontend        │
     │                    │                    │
     │                    │                    │ 6. Deploy script
     │                    │                    │    (local → API)
     │                    │                    │
     │                    │                    │ 7. SQL executed
     │                    │                    │    in production
```

---

## Step-by-Step: Production Backend Deployment

### Step 1: Code is Ready in `develop` Branch

```bash
# You've been working on develop branch
git checkout develop
git status
# Shows: All changes committed and pushed
```

**What's in `develop`:**
- Updated SQL/RPC functions in `supabase/remote_rpcs/`
- Updated Edge Functions in `supabase/functions/`
- All changes tested on staging Supabase
- All changes tested with production frontend

---

### Step 2: Test Production Frontend with Staging Backend ⚠️ MANDATORY

```bash
./scripts/test_production_frontend_with_staging.sh
```

**What happens:**
1. Script guides you to build current production iOS version
2. Connect it to staging backend (using override)
3. You manually test critical flows
4. Script blocks until you confirm all tests pass

**Why:** Ensures old app versions won't break when you deploy new backend.

---

### Step 3: Merge `develop` → `main` (Git Only)

```bash
git checkout main
git pull origin main
git merge develop
git push origin main
```

**What happens:**
- Code moves from `develop` branch to `main` branch
- This is **ONLY version control** - nothing deploys yet
- Production Supabase is still running old code

**Current state:**
- ✅ Git `main` branch has new code
- ❌ Production Supabase still has old code

---

### Step 4: Deploy to Production (The Actual Deployment)

```bash
./scripts/deploy_to_production.sh
```

**What this script does:**

1. **Reads SQL files from local git repo**
   ```bash
   # Script reads files like:
   # supabase/remote_rpcs/rpc_create_commitment.sql
   # supabase/remote_rpcs/rpc_preview_max_charge.sql
   # etc.
   ```

2. **Sources production credentials from `.env`**
   ```bash
   source .env
   # Uses: PRODUCTION_SUPABASE_URL
   # Uses: PRODUCTION_SUPABASE_SECRET_KEY
   ```

3. **Calls Supabase API directly**
   ```bash
   # For each SQL file, makes API call:
   curl -X POST "${PRODUCTION_SUPABASE_URL}/rest/v1/rpc/rpc_execute_sql" \
     -H "Authorization: Bearer ${PRODUCTION_SUPABASE_SECRET_KEY}" \
     -d '{"p_sql": "<SQL_CONTENT>"}'
   ```

4. **Executes SQL in production database**
   - Creates/updates RPC functions
   - Updates database schema if needed
   - Production Supabase now has new code

**Result:**
- ✅ Production Supabase now running new code
- ✅ New RPC functions available
- ✅ Old app versions still work (if backward compatible)

---

### Step 5: Deploy Edge Functions (Manual)

Edge Functions require manual deployment in Supabase Dashboard:

1. Go to Supabase Dashboard → Edge Functions
2. For each function (`rapid-service`, `billing-status`, `weekly-close`, `bright-service`):
   - Select the function
   - Copy-paste new code from `supabase/functions/[name]/index.ts`
   - Click Deploy

**Why manual:** Supabase doesn't have CLI deployment for Edge Functions (or it's complex to set up).

---

### Step 6: Verify Production

```bash
# Test that new functions work
curl -X POST "${PRODUCTION_SUPABASE_URL}/rest/v1/rpc/rpc_preview_max_charge" \
  -H "Authorization: Bearer ${PRODUCTION_SUPABASE_SECRET_KEY}" \
  -d '{"p_deadline_date": "2024-12-16", ...}'

# Check Supabase Dashboard → Database → Functions
# Verify new functions exist
```

---

## Complete Flow Example

### Scenario: Deploying Authorization Fee Fix

**Monday-Wednesday: Development**
```bash
git checkout develop
git checkout -b feat/fix-auth-calculation
# Edit: supabase/remote_rpcs/calculate_max_charge_cents.sql
# Edit: supabase/remote_rpcs/rpc_preview_max_charge.sql
./scripts/deploy_to_staging.sh  # Test on staging
# Test in Xcode (DEBUG = staging)
git commit -m "feat: fix auth calculation"
git checkout develop && git merge feat/fix-auth-calculation
git push origin develop
```

**Thursday: Compatibility Testing**
```bash
./scripts/test_production_frontend_with_staging.sh
# Build production frontend (1.1.0) with staging backend
# Test manually - all flows work ✅
```

**Friday: Production Deployment**
```bash
# 1. Merge to main
git checkout main
git merge develop
git push origin main
# ✅ Git now has new code

# 2. Deploy to production
./scripts/deploy_to_production.sh
# ✅ Production Supabase now has new code

# 3. Deploy Edge Functions (if changed)
# Manual in Supabase Dashboard

# 4. Verify
# Test in production, check logs
```

**Result:**
- ✅ Production backend updated
- ✅ Old app versions (1.1.0) still work
- ✅ New app version (1.2.0) can use new features

---

## What Gets Deployed

### SQL/RPC Functions (Automatic via Script)
- All files in `supabase/remote_rpcs/*.sql`
- Deployed via `rpc_execute_sql` API call
- Examples:
  - `rpc_create_commitment.sql`
  - `rpc_preview_max_charge.sql`
  - `calculate_max_charge_cents.sql`

### Edge Functions (Manual)
- Files in `supabase/functions/[name]/index.ts`
- Deployed manually in Supabase Dashboard
- Examples:
  - `rapid-service/index.ts`
  - `billing-status/index.ts`
  - `weekly-close/index.ts`

### Database Schema Changes
- If you modify tables/columns, include in SQL files
- Deployed via same script
- Example: `ALTER TABLE commitments ADD COLUMN ...`

---

## Important Notes

### ⚠️ Git Push ≠ Deployment

```bash
git push origin main  # ← This does NOT deploy!
./scripts/deploy_to_production.sh  # ← This DOES deploy!
```

**Git push:**
- ✅ Updates code in GitHub
- ❌ Does NOT update production Supabase
- ❌ Does NOT run any deployment

**Deploy script:**
- ✅ Reads code from local git repo
- ✅ Calls Supabase API directly
- ✅ Updates production database

### ⚠️ Backward Compatibility

Before deploying:
- ✅ Test production frontend with staging backend
- ✅ Ensure old app versions still work
- ✅ Check version support in RPC functions

### ⚠️ Rollback

If something breaks:
```bash
# Revert to previous commit
git checkout HEAD~1 -- supabase/remote_rpcs/[function].sql

# Deploy old version
./scripts/deploy_to_production.sh
```

---

## Summary

**Production Backend Deployment = 3 Steps:**

1. **Merge to main** (git only - version control)
2. **Run deploy script** (actual deployment - local → Supabase API)
3. **Deploy Edge Functions** (manual in Dashboard)

**Key Point:** Git stores code, scripts deploy code. They're separate steps.

