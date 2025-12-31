# Security Deployment Checklist

**Date**: 2025-12-31  
**Task**: Task 9 - Deploy to staging  
**Status**: ⏳ In Progress

---

## Pre-Deployment Checklist

### ✅ Migrations Ready

- [x] `20251231001942_add_auth_check_to_rpc_preview_max_charge.sql` - Applied
- [x] `20251231001943_restrict_rpc_setup_test_data_to_test_users.sql` - Ready
- [x] `20251231002000_create_rate_limits_table.sql` - Applied

### ✅ Edge Functions Updated

- [x] `billing-status` - Rate limiting + auth
- [x] `rapid-service` - Rate limiting + auth
- [x] `super-service` - Rate limiting + auth

### ✅ Shared Utilities

- [x] `_shared/rateLimit.ts` - Rate limiting helper
- [x] `_shared/validation.ts` - Input validation helper

---

## Step 1: Apply Pending Migrations

### Migration: `20251231001943_restrict_rpc_setup_test_data_to_test_users.sql`

**Status**: ⏳ Pending

**Action**: Apply via Supabase Dashboard or CLI

```bash
# Option 1: Via CLI
cd supabase
supabase db push --linked

# Option 2: Via Dashboard
# 1. Go to Supabase Dashboard → SQL Editor
# 2. Copy contents of migration file
# 3. Run SQL
```

**Verification**:
```sql
-- Verify function requires test user
SELECT public.rpc_setup_test_data();
-- Should fail for non-test users
```

---

## Step 2: Deploy Edge Functions

### Functions to Deploy

1. **billing-status**
   - ✅ Rate limiting (10 req/min)
   - ✅ Authentication required
   - ✅ Input validation

2. **rapid-service**
   - ✅ Rate limiting (10 req/min)
   - ✅ Authentication required
   - ✅ Input validation

3. **super-service**
   - ✅ Rate limiting (30 req/min)
   - ✅ Authentication required
   - ✅ Input validation

### Deployment Commands

```bash
cd supabase/functions

# Deploy billing-status
supabase functions deploy billing-status

# Deploy rapid-service
supabase functions deploy rapid-service

# Deploy super-service
supabase functions deploy super-service
```

**Note**: Functions were already deployed earlier, but verify they're up to date.

---

## Step 3: Verify Deployments

### Check Function Logs

1. Go to Supabase Dashboard → Edge Functions
2. Check each function's logs for errors
3. Verify functions are active

### Verify Rate Limiting

1. Check that `rate_limits` table exists:
   ```sql
   SELECT * FROM public.rate_limits LIMIT 1;
   ```

2. Verify rate limiting is working (test with multiple requests)

### Verify Authentication

1. Test each function without auth → should return 401
2. Test each function with valid auth → should work

---

## Step 4: Smoke Tests

### Critical User Flows

1. **Sign In**
   - [ ] User can sign in with Apple
   - [ ] Token stored in Keychain (not UserDefaults)
   - [ ] User stays signed in after app restart

2. **Create Commitment**
   - [ ] User can create commitment via `super-service`
   - [ ] Rate limiting works (test with multiple rapid requests)
   - [ ] Input validation works (test with invalid data)

3. **Billing Status**
   - [ ] User can check billing status via `billing-status`
   - [ ] Rate limiting works
   - [ ] Authentication required

4. **Payment Processing**
   - [ ] User can process payment via `rapid-service`
   - [ ] Rate limiting works
   - [ ] Authentication required

5. **Data Access**
   - [ ] User can only see their own data (RLS)
   - [ ] User cannot access other users' data

---

## Step 5: Post-Deployment Verification

### Database

- [ ] `rate_limits` table exists and is accessible
- [ ] RPC functions have proper security checks
- [ ] RLS policies are active

### Edge Functions

- [ ] All functions deployed successfully
- [ ] No errors in function logs
- [ ] Rate limiting headers present in responses
- [ ] Authentication working correctly

### iOS App

- [ ] App can authenticate
- [ ] Tokens stored in Keychain
- [ ] App can create commitments
- [ ] App can check billing status
- [ ] App can process payments

---

## Rollback Plan

If issues are found:

1. **Rollback Migrations**: 
   - Revert SQL changes via Supabase Dashboard
   - Or restore from backup

2. **Rollback Edge Functions**:
   - Redeploy previous versions
   - Or disable functions temporarily

3. **Rollback iOS**:
   - Revert to previous app version
   - Or disable Keychain migration temporarily

---

## Deployment Log

### 2025-12-31

- [ ] Migrations applied
- [ ] Edge Functions deployed
- [ ] Smoke tests passed
- [ ] Issues found: (list any issues)
- [ ] Issues resolved: (list resolutions)

---

**Next Steps**: After successful deployment, proceed to Task 10: Document implementation

