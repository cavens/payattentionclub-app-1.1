# Phase 7: Manual Verification Guide

## Step-by-Step Verification Process

Follow this guide to manually verify all components in both environments.

---

## Part 1: Staging Environment

### Step 1.1: Verify Edge Functions

**Go to:** https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions

**Check:**
- [ ] `billing-status` - deployed
- [ ] `weekly-close` - deployed
- [ ] `stripe-webhook` - deployed
- [ ] `super-service` - deployed
- [ ] `rapid-service` - deployed
- [ ] `bright-service` - deployed
- [ ] `quick-handler` - deployed
- [ ] `admin-close-week-now` - deployed

**Total:** Should see 8 functions

**If any are missing:** Note which ones and we'll deploy them.

---

### Step 1.2: Verify Edge Function Secrets

**Go to:** https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/functions

**Check:**
- [ ] `STRIPE_SECRET_KEY` exists (should be test key starting with `sk_test_`)
- [ ] `STRIPE_WEBHOOK_SECRET` exists (should start with `whsec_`)

**To verify values match `.env`:**
- Compare with `STAGING_STRIPE_SECRET_KEY` in `.env`
- Compare with `STAGING_STRIPE_WEBHOOK_SECRET` in `.env`

**If missing:** We'll set them using the script.

---

### Step 1.3: Verify Stripe Webhook

**Go to:** https://dashboard.stripe.com/test/webhooks

**Check:**
- [ ] Webhook endpoint exists for staging
- [ ] URL: `https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook`
- [ ] Status: Enabled
- [ ] Events selected (at minimum: `payment_intent.succeeded`, `payment_intent.failed`)
- [ ] Signing secret matches `STAGING_STRIPE_WEBHOOK_SECRET` in `.env`

**If missing:** We'll create it.

---

### Step 1.4: Verify Apple Sign-In

**Go to:** https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/auth/providers

**Click on:** Apple provider

**Check:**
- [ ] Provider is enabled (toggle is ON)
- [ ] Services ID is set
- [ ] Secret Key (.p8) is uploaded
- [ ] Team ID is set
- [ ] Key ID is set
- [ ] Redirect URLs include staging URL

**If not enabled:** See `docs/ENABLE_APPLE_SIGNIN.md` for setup instructions.

---

### Step 1.5: Verify Cron Jobs

**Go to:** https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/database/cron

**Check:**
- [ ] `weekly-close-staging` - Active, schedule: `0 17 * * 1`
- [ ] `Weekly-Settlement` - Active, schedule: `0 12 * * 2`
- [ ] `settlement-reconcile` - Active, schedule: `0 */6 * * *`

**Total:** Should see 3 active jobs

**If any are missing:** We can add them via SQL.

---

### Step 1.6: Verify Edge Function Logs

**Go to:** https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs

**Check:**
- [ ] Recent log entries visible (from our test calls)
- [ ] HTTP status: 200 (success)
- [ ] No error messages
- [ ] Timestamp shows recent invocation

**If no logs:** The function may not have been called yet, or logs are empty.

---

### Step 1.7: Verify API Keys

**Go to:** https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/api

**Check:**
- [ ] Project URL matches: `https://auqujbppoytkeqdsgrbl.supabase.co`
- [ ] `anon` public key matches `STAGING_SUPABASE_ANON_KEY` in `.env`
- [ ] `service_role` secret key matches `STAGING_SUPABASE_SERVICE_ROLE_KEY` in `.env` (first 20 chars)

**Note:** Service role key is hidden, but you can verify the first few characters match.

---

## Part 2: Production Environment

### Step 2.1: Verify Edge Functions

**Go to:** https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions

**Check:**
- [ ] All 8 functions deployed (same as staging)
- [ ] `billing-status` - deployed
- [ ] `weekly-close` - deployed
- [ ] `stripe-webhook` - deployed
- [ ] `super-service` - deployed
- [ ] `rapid-service` - deployed
- [ ] `bright-service` - deployed
- [ ] `quick-handler` - deployed
- [ ] `admin-close-week-now` - deployed

---

### Step 2.2: Verify Edge Function Secrets

**Go to:** https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/functions

**Check:**
- [ ] `STRIPE_SECRET_KEY` exists (should be LIVE key starting with `sk_live_`)
- [ ] `STRIPE_WEBHOOK_SECRET` exists (should start with `whsec_`)

**To verify values match `.env`:**
- Compare with `PRODUCTION_STRIPE_SECRET_KEY` in `.env`
- Compare with `PRODUCTION_STRIPE_WEBHOOK_SECRET` in `.env`

---

### Step 2.3: Verify Stripe Webhook

**Go to:** https://dashboard.stripe.com/webhooks

**Make sure you're in LIVE mode** (toggle in top right)

**Check:**
- [ ] Webhook endpoint exists for production
- [ ] URL: `https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook`
- [ ] Status: Enabled
- [ ] Events selected (same as staging)
- [ ] Signing secret matches `PRODUCTION_STRIPE_WEBHOOK_SECRET` in `.env`

---

### Step 2.4: Verify Apple Sign-In

**Go to:** https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/providers

**Click on:** Apple provider

**Check:**
- [ ] Provider is enabled (toggle is ON)
- [ ] Same OAuth key as staging (can use same key for both)
- [ ] Redirect URLs include production URL

---

### Step 2.5: Verify Cron Jobs

**Go to:** https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/database/cron

**Check:**
- [ ] `weekly-close-production` - Active, schedule: `0 17 * * 1`
- [ ] `Weekly-Settlement` - Active, schedule: `0 12 * * 2`
- [ ] `settlement-reconcile` - Active, schedule: `0 */6 * * *`

**Total:** Should see 3 active jobs

---

### Step 2.6: Verify Edge Function Logs

**Go to:** https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs

**Check:**
- [ ] Recent log entries visible (from our test calls)
- [ ] HTTP status: 200 (success)
- [ ] No error messages

---

### Step 2.7: Verify API Keys

**Go to:** https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/api

**Check:**
- [ ] Project URL matches: `https://whdftvcrtrsnefhprebj.supabase.co`
- [ ] `anon` public key matches `PRODUCTION_SUPABASE_ANON_KEY` in `.env`
- [ ] `service_role` secret key matches `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY` in `.env` (first 20 chars)

---

## Part 3: Quick Verification Scripts

After manual verification, run these to double-check:

```bash
# Verify cron jobs
./scripts/run_sql_via_api.sh staging "SELECT jobid, jobname, schedule, active FROM cron.job;"
./scripts/run_sql_via_api.sh production "SELECT jobid, jobname, schedule, active FROM cron.job;"

# Verify setup
curl -X POST "${STAGING_SUPABASE_URL}/rest/v1/rpc/rpc_verify_setup" \
  -H "apikey: ${STAGING_SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${STAGING_SUPABASE_SERVICE_ROLE_KEY}"

curl -X POST "${PRODUCTION_SUPABASE_URL}/rest/v1/rpc/rpc_verify_setup" \
  -H "apikey: ${PRODUCTION_SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${PRODUCTION_SUPABASE_SERVICE_ROLE_KEY}"
```

---

## Verification Results Template

After completing verification, update `docs/PHASE7_RESULTS.md` with:

- ✅ = Verified and working
- ⚠️ = Needs attention
- ❌ = Failed or missing

---

## Common Issues & Fixes

### Edge Function Missing
**Fix:** Deploy using Supabase CLI or Dashboard

### Secret Missing
**Fix:** Use `scripts/set_webhook_secrets.sh` or set manually in Dashboard

### Webhook Missing
**Fix:** Create in Stripe Dashboard → Webhooks

### Apple Sign-In Not Enabled
**Fix:** See `docs/ENABLE_APPLE_SIGNIN.md`

### Cron Job Missing
**Fix:** Run SQL from `supabase/sql-drafts/setup_cron_staging.sql` or `setup_cron_production.sql`

---

**Ready to start?** Let's go through each step together!

