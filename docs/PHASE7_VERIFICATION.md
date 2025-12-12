# Phase 7: Verification Checklist

## Overview

Phase 7 is the final verification step to ensure both staging and production environments are fully configured and working correctly. This phase involves systematic testing of all components.

**Time Estimate:** ~30-45 minutes

---

## Staging Environment Verification

### ✅ 1. Supabase Project Setup

- [ ] **Project exists and is accessible**
  - URL: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl
  - Status: Active and running

- [ ] **API Keys are correct**
  - Anon key matches `.env` file (`STAGING_SUPABASE_ANON_KEY`)
  - Service role key matches `.env` file (`STAGING_SUPABASE_SERVICE_ROLE_KEY`)
  - Verify in: Settings → API

### ✅ 2. Database Schema

- [ ] **All tables exist**
  ```sql
  SELECT table_name 
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
  ORDER BY table_name;
  ```
  Expected tables:
  - `commitments`
  - `daily_usage`
  - `user_week_penalties`
  - `weekly_pools`
  - `payments`
  - `users`
  - `_internal_config`

- [ ] **RPC functions deployed**
  ```sql
  SELECT routine_name 
  FROM information_schema.routines 
  WHERE routine_schema = 'public' 
  AND routine_type = 'FUNCTION'
  ORDER BY routine_name;
  ```
  Key functions to verify:
  - `rpc_create_commitment`
  - `rpc_sync_daily_usage`
  - `rpc_get_week_status`
  - `rpc_delete_user_completely`
  - `call_weekly_close`
  - `rpc_list_cron_jobs`
  - `rpc_get_cron_history`

### ✅ 3. Edge Functions

- [ ] **All Edge Functions deployed**
  - Check: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions
  - Expected functions:
    - `billing-status`
    - `weekly-close`
    - `stripe-webhook`
    - `super-service`
    - `rapid-service`
    - `bright-service`
    - `quick-handler`
    - `admin-close-week-now`

- [ ] **Edge Function secrets set**
  - `STRIPE_SECRET_KEY` (test key)
  - `STRIPE_WEBHOOK_SECRET` (staging webhook secret)
  - Verify in: Settings → Edge Functions → Secrets

### ✅ 4. Stripe Configuration

- [ ] **Stripe webhook configured**
  - URL: `https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook`
  - Mode: Test mode
  - Events: `payment_intent.succeeded`, `payment_intent.failed`, etc.
  - Signing secret matches `.env` (`STAGING_STRIPE_WEBHOOK_SECRET`)
  - Verify in: Stripe Dashboard → Webhooks (Test Mode)

- [ ] **Stripe keys match**
  - Test publishable key in iOS `Config.swift` matches Stripe Dashboard
  - Test secret key in Supabase secrets matches Stripe Dashboard

### ✅ 5. Cron Jobs

- [ ] **All cron jobs configured**
  ```sql
  SELECT jobid, jobname, schedule, active 
  FROM cron.job 
  ORDER BY jobid;
  ```
  Expected jobs:
  - `weekly-close-staging` (Monday 17:00 UTC)
  - `Weekly-Settlement` (Tuesday 12:00 UTC)
  - `settlement-reconcile` (Every 6 hours)

- [ ] **Service role key set in `_internal_config`**
  ```sql
  SELECT key, LEFT(value, 20) || '...' as preview, updated_at
  FROM public._internal_config
  WHERE key = 'service_role_key';
  ```

- [ ] **Test `call_weekly_close()` function**
  ```sql
  SELECT public.call_weekly_close();
  ```
  Then check Edge Function logs for successful invocation.

### ✅ 6. Authentication (Apple Sign-In)

- [ ] **Apple Sign-In enabled**
  - Provider enabled in Supabase Dashboard
  - Services ID configured
  - Secret key (.p8) uploaded
  - Team ID and Key ID set
  - Redirect URLs configured
  - Verify in: Authentication → Providers → Apple

- [ ] **Test sign-in flow**
  - Build iOS app in Debug mode (should use staging)
  - Attempt to sign in with Apple
  - Verify successful authentication
  - Check `auth.users` table for new user

### ✅ 7. iOS App Connection

- [ ] **App connects to staging in Debug mode**
  - Build and run in Xcode (Debug configuration)
  - Check logs for staging Supabase URL
  - Verify connection successful

- [ ] **Environment switching works**
  - Debug builds → Staging
  - Release builds → Production
  - Verify in `Config.swift` logic

---

## Production Environment Verification

### ✅ 1. Supabase Project Setup

- [ ] **Project exists and is accessible**
  - URL: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj
  - Status: Active and running

- [ ] **API Keys are correct**
  - Anon key matches `.env` file (`PRODUCTION_SUPABASE_ANON_KEY`)
  - Service role key matches `.env` file (`PRODUCTION_SUPABASE_SERVICE_ROLE_KEY`)
  - Verify in: Settings → API

### ✅ 2. Database Schema

- [ ] **All tables exist** (same as staging)
- [ ] **RPC functions deployed** (same as staging)

### ✅ 3. Edge Functions

- [ ] **All Edge Functions deployed** (same as staging)
- [ ] **Edge Function secrets set**
  - `STRIPE_SECRET_KEY` (live key)
  - `STRIPE_WEBHOOK_SECRET` (production webhook secret)

### ✅ 4. Stripe Configuration

- [ ] **Stripe webhook configured**
  - URL: `https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook`
  - Mode: Live mode
  - Events: Same as staging
  - Signing secret matches `.env` (`PRODUCTION_STRIPE_WEBHOOK_SECRET`)
  - Verify in: Stripe Dashboard → Webhooks (Live Mode)

- [ ] **Stripe keys match**
  - Live publishable key in iOS `Config.swift` matches Stripe Dashboard
  - Live secret key in Supabase secrets matches Stripe Dashboard

### ✅ 5. Cron Jobs

- [ ] **All cron jobs configured**
  ```sql
  SELECT jobid, jobname, schedule, active 
  FROM cron.job 
  ORDER BY jobid;
  ```
  Expected jobs:
  - `weekly-close-production` (Monday 17:00 UTC)
  - `Weekly-Settlement` (Tuesday 12:00 UTC)
  - `settlement-reconcile` (Every 6 hours)

- [ ] **Service role key set in `_internal_config`**
- [ ] **Test `call_weekly_close()` function**

### ✅ 6. Authentication (Apple Sign-In)

- [ ] **Apple Sign-In enabled** (same OAuth key as staging)
- [ ] **Redirect URLs configured for production**

### ✅ 7. iOS App Connection

- [ ] **App connects to production in Release mode**
  - Build Archive in Xcode (Release configuration)
  - Verify production Supabase URL is used
  - ⚠️ **DO NOT TEST WITH REAL MONEY UNTIL READY**

---

## End-to-End Testing

### Staging End-to-End Test

1. [ ] **Sign up with Apple**
   - Create new account
   - Verify user created in `auth.users` and `public.users`

2. [ ] **Create a commitment**
   - Set commitment amount and duration
   - Verify commitment saved in database

3. [ ] **Complete payment setup**
   - Add payment method (Stripe test card)
   - Verify SetupIntent created and confirmed
   - Check `payments` table

4. [ ] **Test usage tracking**
   - Use app for a day
   - Verify daily usage synced to backend
   - Check `daily_usage` table

5. [ ] **Test billing status**
   - Check billing status endpoint
   - Verify correct status returned

6. [ ] **Test webhook (optional)**
   - Trigger test webhook via Stripe CLI
   - Verify webhook received and processed

### Production End-to-End Test

⚠️ **WARNING: Only test with small amounts or test mode if possible**

1. [ ] **Verify production environment variables**
2. [ ] **Test authentication flow**
3. [ ] **Verify payment setup (use test mode if available)**
4. [ ] **Check all Edge Functions are accessible**

---

## Automated Verification Scripts

### Quick Verification

```bash
# Verify cron jobs in both environments
./scripts/verify_phase6.sh both

# List all cron jobs
./scripts/run_sql_via_api.sh staging "SELECT jobid, jobname, schedule, active FROM cron.job;"
./scripts/run_sql_via_api.sh production "SELECT jobid, jobname, schedule, active FROM cron.job;"

# Test call_weekly_close
./scripts/run_sql_via_api.sh staging "SELECT public.call_weekly_close();"
./scripts/run_sql_via_api.sh production "SELECT public.call_weekly_close();"
```

### iOS Configuration Verification

```bash
# Verify iOS Config.swift settings
./scripts/verify_ios_config.sh
```

---

## Common Issues & Solutions

### Issue: Cron job not running

**Check:**
1. Is `pg_cron` extension enabled?
2. Is the job `active = true`?
3. Is the service role key set in `_internal_config`?
4. Check cron job execution history

**Solution:**
```sql
-- Check extension
SELECT * FROM pg_extension WHERE extname = 'pg_cron';

-- Check job status
SELECT * FROM cron.job WHERE jobname = 'weekly-close-staging';

-- Check service role key
SELECT * FROM public._internal_config WHERE key = 'service_role_key';
```

### Issue: Edge Function not accessible

**Check:**
1. Is the function deployed?
2. Are secrets set correctly?
3. Check Edge Function logs for errors

**Solution:**
- Redeploy function: `supabase functions deploy [function-name]`
- Verify secrets: Settings → Edge Functions → Secrets

### Issue: Apple Sign-In not working

**Check:**
1. Is provider enabled in Supabase Dashboard?
2. Are Services ID, Team ID, Key ID correct?
3. Is the secret key (.p8) uploaded?
4. Are redirect URLs configured?

**Solution:**
- See `docs/ENABLE_APPLE_SIGNIN.md` for detailed steps

### Issue: iOS app connecting to wrong environment

**Check:**
1. Build configuration (Debug vs Release)
2. `Config.swift` environment logic
3. Xcode scheme settings

**Solution:**
- Verify `AppConfig.environment` logic in `Config.swift`
- Check Xcode build configuration

---

## Final Checklist

### Before Going Live

- [ ] All staging tests pass
- [ ] All production verification items complete
- [ ] Documentation updated
- [ ] Environment variables secured (not in git)
- [ ] Monitoring/alerts set up (optional)
- [ ] Backup strategy in place (optional)
- [ ] Rollback plan documented (optional)

---

## Next Steps After Phase 7

1. **Monitor first scheduled cron job runs**
   - Weekly close: Next Monday at 17:00 UTC
   - Weekly settlement: Next Tuesday at 12:00 UTC
   - Settlement reconcile: Every 6 hours

2. **Set up monitoring** (optional)
   - Edge Function error alerts
   - Cron job failure notifications
   - Database health checks

3. **Document any environment-specific differences**
   - Note any customizations
   - Document troubleshooting steps

4. **Plan for production launch**
   - Final testing with real users (beta)
   - Load testing (if needed)
   - Security audit (if needed)

---

## Quick Reference Links

### Staging
- Dashboard: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl
- Cron Jobs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/database/cron
- Edge Functions: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions

### Production
- Dashboard: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj
- Cron Jobs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/database/cron
- Edge Functions: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions

---

**Phase 7 Status:** Ready to begin verification


