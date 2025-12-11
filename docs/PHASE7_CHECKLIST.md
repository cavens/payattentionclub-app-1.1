# Phase 7: Manual Verification Checklist

Print this checklist and check off each item as you verify it.

---

## ✅ STAGING ENVIRONMENT

### Edge Functions
- [ ] Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions
- [ ] `billing-status` - visible and deployed
- [ ] `weekly-close` - visible and deployed
- [ ] `stripe-webhook` - visible and deployed
- [ ] `super-service` - visible and deployed
- [ ] `rapid-service` - visible and deployed
- [ ] `bright-service` - visible and deployed
- [ ] `quick-handler` - visible and deployed
- [ ] `admin-close-week-now` - visible and deployed
- [ ] **Total: 8 functions** ✅

### Edge Function Secrets
- [ ] Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/functions
- [ ] `STRIPE_SECRET_KEY` exists (test key: `sk_test_...`)
- [ ] `STRIPE_WEBHOOK_SECRET` exists (`whsec_...`)
- [ ] Values match `.env` file

### Cron Jobs
- [ ] Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/database/cron
- [ ] `weekly-close-staging` - Active, Monday 17:00 UTC
- [ ] `Weekly-Settlement` - Active, Tuesday 12:00 UTC
- [ ] `settlement-reconcile` - Active, Every 6 hours
- [ ] **Total: 3 jobs** ✅

### Apple Sign-In
- [ ] Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/auth/providers
- [ ] Apple provider is **enabled** (toggle ON)
- [ ] Services ID configured
- [ ] Secret key (.p8) uploaded
- [ ] Team ID set
- [ ] Key ID set
- [ ] Redirect URLs include staging URL

### Edge Function Logs
- [ ] Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs
- [ ] Recent log entries visible
- [ ] HTTP 200 responses
- [ ] No error messages

### API Keys
- [ ] Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/api
- [ ] Project URL correct: `https://auqujbppoytkeqdsgrbl.supabase.co`
- [ ] Anon key matches `.env` (`STAGING_SUPABASE_ANON_KEY`)
- [ ] Service role key matches `.env` (first 20 chars)

### Stripe Webhook (Test Mode)
- [ ] Go to: https://dashboard.stripe.com/test/webhooks
- [ ] Webhook endpoint exists
- [ ] URL: `https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook`
- [ ] Status: Enabled
- [ ] Events selected (payment_intent.succeeded, etc.)
- [ ] Signing secret matches `.env` (`STAGING_STRIPE_WEBHOOK_SECRET`)

---

## ✅ PRODUCTION ENVIRONMENT

### Edge Functions
- [ ] Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
- [ ] `billing-status` - visible and deployed
- [ ] `weekly-close` - visible and deployed
- [ ] `stripe-webhook` - visible and deployed
- [ ] `super-service` - visible and deployed
- [ ] `rapid-service` - visible and deployed
- [ ] `bright-service` - visible and deployed
- [ ] `quick-handler` - visible and deployed
- [ ] `admin-close-week-now` - visible and deployed
- [ ] **Total: 8 functions** ✅

### Edge Function Secrets
- [ ] Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/functions
- [ ] `STRIPE_SECRET_KEY` exists (live key: `sk_live_...`)
- [ ] `STRIPE_WEBHOOK_SECRET` exists (`whsec_...`)
- [ ] Values match `.env` file

### Cron Jobs
- [ ] Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/database/cron
- [ ] `weekly-close-production` - Active, Monday 17:00 UTC
- [ ] `Weekly-Settlement` - Active, Tuesday 12:00 UTC
- [ ] `settlement-reconcile` - Active, Every 6 hours
- [ ] **Total: 3 jobs** ✅

### Apple Sign-In
- [ ] Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/providers
- [ ] Apple provider is **enabled** (toggle ON)
- [ ] Same OAuth key as staging (can reuse)
- [ ] Redirect URLs include production URL

### Edge Function Logs
- [ ] Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs
- [ ] Recent log entries visible
- [ ] HTTP 200 responses
- [ ] No error messages

### API Keys
- [ ] Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/api
- [ ] Project URL correct: `https://whdftvcrtrsnefhprebj.supabase.co`
- [ ] Anon key matches `.env` (`PRODUCTION_SUPABASE_ANON_KEY`)
- [ ] Service role key matches `.env` (first 20 chars)

### Stripe Webhook (Live Mode)
- [ ] Go to: https://dashboard.stripe.com/webhooks
- [ ] **Make sure you're in LIVE mode** (toggle in top right)
- [ ] Webhook endpoint exists
- [ ] URL: `https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook`
- [ ] Status: Enabled
- [ ] Events selected (payment_intent.succeeded, etc.)
- [ ] Signing secret matches `.env` (`PRODUCTION_STRIPE_WEBHOOK_SECRET`)

---

## 📝 Verification Summary

**Staging:**
- Edge Functions: ___/8
- Secrets: ___/2
- Cron Jobs: ___/3
- Apple Sign-In: ✅ / ❌
- Webhook: ✅ / ❌

**Production:**
- Edge Functions: ___/8
- Secrets: ___/2
- Cron Jobs: ___/3
- Apple Sign-In: ✅ / ❌
- Webhook: ✅ / ❌

**Overall Status:** ✅ Complete / ⚠️ Needs Attention / ❌ Issues Found

**Notes:**
_____________________________________________________________
_____________________________________________________________
_____________________________________________________________

---

**Date Completed:** _______________
**Verified By:** _______________

