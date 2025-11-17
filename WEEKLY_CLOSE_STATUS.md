# Weekly Close Implementation - Current Status

## What We're Working On

**Goal:** Implement the weekly close functionality (Phase 6.2 from BACKEND_BRIEFING.md)

**Step 1.3:** (To be determined after we see what's deployed)

---

## Current Local Files

### Edge Functions (TypeScript)
- ✅ `billing-status-updated.ts` - Billing status check
- ✅ `confirm-setup-intent-edge-function.ts` - Setup intent confirmation
- ✅ `create-commitment-edge-function.ts` - Create commitment
- ✅ `super-service-edge-function.ts` - Service function
- ❌ `weekly-close` - **MISSING** (needs to be created/downloaded)
- ❌ `stripe-webhook` - **MISSING** (needs to be created/downloaded)
- ❌ `admin-close-week-now` - **MISSING** (dev tool)

### RPC Functions (SQL)
- ✅ `rpc_report_usage_fixed.sql` - Report usage (fixed version)
- ✅ `rpc_create_commitment_updated.sql` - Create commitment (updated)
- ❌ `rpc_update_monitoring_status` - **MISSING** (need to check if exists)
- ❌ `rpc_get_week_status` - **MISSING** (need to check if exists)

---

## Next Steps

### 1. Download from Supabase (Do This First)

You need to link to your Supabase project and pull the functions. See `DOWNLOAD_SUPABASE_FUNCTIONS.md` for detailed instructions.

**Quick version:**
```bash
# Link to your project (get project ref from Supabase Dashboard)
supabase link --project-ref YOUR_PROJECT_REF

# Pull Edge Functions
supabase functions pull

# Check what RPC functions exist in database
# (Use Supabase Dashboard → SQL Editor)
```

### 2. Compare Local vs Online

After downloading, we'll:
- Compare what's deployed vs what's local
- Identify what's missing
- Determine what Step 1.3 should be

### 3. Create Implementation Plan

Once we know what exists, I'll create a detailed Step 1.3 plan for the weekly close implementation.

---

## What Step 1.3 Likely Involves

Based on BACKEND_BRIEFING.md Phase 6.2, the weekly-close function needs to:

1. **Determine last week** - Calculate which week just ended
2. **Insert estimated rows** - For users who revoked monitoring
3. **Recompute totals** - Update user_week_penalties and weekly_pools
4. **Create Stripe charges** - For each user with balance
5. **Close weekly pool** - Mark pool as closed

---

## Questions to Answer

1. Is `weekly-close` Edge Function already deployed?
2. Are all RPC functions deployed?
3. What's the current state of the database schema?
4. Is Stripe integration set up?

---

## Action Items

- [ ] Link Supabase project: `supabase link --project-ref XXX`
- [ ] Pull Edge Functions: `supabase functions pull`
- [ ] Check RPC functions in database
- [ ] Compare local vs online versions
- [ ] Create Step 1.3 implementation plan
- [ ] Implement weekly-close function


