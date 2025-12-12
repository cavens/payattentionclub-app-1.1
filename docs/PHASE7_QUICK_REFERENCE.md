# Phase 7: Quick Reference Card

## ✅ Automated Verification Results

**Status:** All automated checks passed!

| Component | Staging | Production |
|-----------|---------|------------|
| Cron Jobs | ✅ 3 active | ✅ 3 active |
| Database Tables | ✅ 7/7 | ✅ 7/7 |
| RPC Functions | ✅ 7/7 | ✅ 7/7 |
| Service Role Key | ✅ Set | ✅ Set |
| call_weekly_close() | ✅ Working | ✅ Working |
| iOS Config | ✅ Correct | ✅ Correct |
| .env File | ✅ 12 vars | ✅ 12 vars |

---

## 🔗 Quick Dashboard Links

### Staging Environment

**Project Dashboard:**
- Main: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl

**Database:**
- Tables: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/editor
- Cron Jobs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/database/cron
- SQL Editor: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/sql/new

**Edge Functions:**
- Functions List: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions
- weekly-close Logs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs
- billing-status Logs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/billing-status/logs
- stripe-webhook Logs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/stripe-webhook/logs

**Settings:**
- API Keys: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/api
- Edge Function Secrets: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/functions
- Authentication: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/auth/providers

---

### Production Environment

**Project Dashboard:**
- Main: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj

**Database:**
- Tables: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/editor
- Cron Jobs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/database/cron
- SQL Editor: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/sql/new

**Edge Functions:**
- Functions List: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
- weekly-close Logs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs
- billing-status Logs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/billing-status/logs
- stripe-webhook Logs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/stripe-webhook/logs

**Settings:**
- API Keys: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/api
- Edge Function Secrets: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/functions
- Authentication: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/providers

---

## ✅ Manual Verification Checklist

### Staging

- [ ] **Edge Functions (8 total)**
  - [ ] billing-status
  - [ ] weekly-close
  - [ ] stripe-webhook
  - [ ] super-service
  - [ ] rapid-service
  - [ ] bright-service
  - [ ] quick-handler
  - [ ] admin-close-week-now

- [ ] **Edge Function Secrets**
  - [ ] `STRIPE_SECRET_KEY` (test key)
  - [ ] `STRIPE_WEBHOOK_SECRET` (staging webhook secret)

- [ ] **Stripe Webhook**
  - [ ] URL: `https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook`
  - [ ] Mode: Test mode
  - [ ] Events selected
  - [ ] Signing secret matches `.env`

- [ ] **Apple Sign-In**
  - [ ] Provider enabled
  - [ ] Services ID configured
  - [ ] Secret key uploaded
  - [ ] Team ID and Key ID set
  - [ ] Redirect URLs configured

- [ ] **Edge Function Logs**
  - [ ] weekly-close: Recent test invocation visible
  - [ ] No errors in logs

### Production

- [ ] **Edge Functions (8 total)** - Same as staging
- [ ] **Edge Function Secrets**
  - [ ] `STRIPE_SECRET_KEY` (live key)
  - [ ] `STRIPE_WEBHOOK_SECRET` (production webhook secret)
- [ ] **Stripe Webhook**
  - [ ] URL: `https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook`
  - [ ] Mode: Live mode
- [ ] **Apple Sign-In** - Same OAuth key as staging
- [ ] **Edge Function Logs** - Recent test invocation visible

---

## 🧪 Quick Test Commands

### Test call_weekly_close()

**Staging:**
```sql
SELECT public.call_weekly_close();
```

**Production:**
```sql
SELECT public.call_weekly_close();
```

Then check Edge Function logs for successful invocation.

### List Cron Jobs

**Staging:**
```sql
SELECT jobid, jobname, schedule, active 
FROM cron.job 
ORDER BY jobid;
```

**Production:**
```sql
SELECT jobid, jobname, schedule, active 
FROM cron.job 
ORDER BY jobid;
```

### Verify Setup

**Staging:**
```sql
SELECT * FROM public.rpc_verify_setup();
```

**Production:**
```sql
SELECT * FROM public.rpc_verify_setup();
```

---

## 📊 Expected Cron Jobs

### Staging
1. `weekly-close-staging` - Monday 17:00 UTC
2. `Weekly-Settlement` - Tuesday 12:00 UTC
3. `settlement-reconcile` - Every 6 hours

### Production
1. `weekly-close-production` - Monday 17:00 UTC
2. `Weekly-Settlement` - Tuesday 12:00 UTC
3. `settlement-reconcile` - Every 6 hours

---

## 🎯 Next Steps

1. Complete manual verification checklist above
2. Run end-to-end test in staging (sign up, create commitment, payment)
3. Verify Edge Function logs show successful invocations
4. Document any issues found
5. Update `docs/PHASE7_RESULTS.md` with final status

---

**Last Updated:** $(date)


