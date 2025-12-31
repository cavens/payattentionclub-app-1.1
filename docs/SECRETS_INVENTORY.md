# Secrets Inventory & Rotation Plan

**Last Updated**: 2025-12-31  
**Status**: ✅ Complete  
**Purpose**: Document all secrets, API keys, and credentials used by Pay Attention Club

---

## Executive Summary

This document inventories all secrets, API keys, and credentials used by the Pay Attention Club application. This inventory is required for:
- Security risk assessment
- Secret rotation planning
- Incident response (knowing what to rotate if compromised)
- Compliance (ensuring no secrets in code)

---

## Secrets Categories

### 1. Supabase Secrets

#### Supabase Secret Key (Staging)
- **Name**: `STAGING_SUPABASE_SECRET_KEY`
- **Location**: Supabase Edge Function secrets (staging environment)
- **Type**: Secret key with full database access (bypasses RLS)
- **Purpose**: 
  - Edge Functions use this to bypass RLS for admin operations
  - Database migrations
  - Admin operations
  - User authentication verification
- **Access**: 
  - Stored in Supabase Dashboard → Project Settings → Edge Functions → Secrets
  - Never stored in code
  - Never committed to git
- **Rotation**: Quarterly (or immediately if compromised)
- **Last Rotated**: Not yet rotated (initial setup)
- **Next Rotation**: 2026-03-31
- **Risk Level**: 🔴 **CRITICAL** - Full database access

#### Supabase Secret Key (Production)
- **Name**: `PRODUCTION_SUPABASE_SECRET_KEY`
- **Location**: Supabase Edge Function secrets (production environment)
- **Type**: Secret key with full database access (bypasses RLS)
- **Purpose**: Same as staging
- **Access**: Same as staging
- **Rotation**: Quarterly (or immediately if compromised)
- **Last Rotated**: Not yet rotated (initial setup)
- **Next Rotation**: 2026-03-31
- **Risk Level**: 🔴 **CRITICAL** - Full database access

#### Supabase URL
- **Name**: `SUPABASE_URL`
- **Location**: Supabase Edge Function environment variables
- **Type**: Public URL (not a secret, but documented here)
- **Purpose**: Supabase project URL for API calls
- **Access**: Public (can be exposed)
- **Rotation**: N/A (changes only if project is recreated)
- **Risk Level**: 🟢 **LOW** - Public information

#### Supabase Anon Key (Public)
- **Name**: `SUPABASE_ANON_KEY` (in iOS app: `SupabaseConfig.publishableKey`)
- **Location**: iOS app code (`SupabaseConfig.swift`)
- **Type**: Public key (safe to expose)
- **Purpose**: Client-side Supabase operations (with RLS)
- **Access**: Public (embedded in app)
- **Rotation**: N/A (public key, safe to expose)
- **Risk Level**: 🟢 **LOW** - Public key, protected by RLS

---

### 2. Stripe Secrets

#### Stripe Secret Key (Test)
- **Name**: `STRIPE_SECRET_KEY_TEST`
- **Location**: Supabase Edge Function secrets
- **Type**: Stripe API secret key (test mode)
- **Purpose**: 
  - Create PaymentIntents (test mode)
  - Create customers (test mode)
  - Process payments (test mode)
  - Webhook verification (test mode)
- **Access**: 
  - Stored in Supabase Dashboard → Edge Functions → Secrets
  - Never stored in code
  - Never committed to git
- **Rotation**: Quarterly (or immediately if compromised)
- **Last Rotated**: Not yet rotated (initial setup)
- **Next Rotation**: 2026-03-31
- **Risk Level**: 🟠 **HIGH** - Can create charges (test mode only)

#### Stripe Secret Key (Production)
- **Name**: `STRIPE_SECRET_KEY`
- **Location**: Supabase Edge Function secrets
- **Type**: Stripe API secret key (live mode)
- **Purpose**: 
  - Create PaymentIntents (live mode)
  - Create customers (live mode)
  - Process payments (live mode)
  - Webhook verification (live mode)
- **Access**: Same as test key
- **Rotation**: Quarterly (or immediately if compromised)
- **Last Rotated**: Not yet rotated (initial setup)
- **Next Rotation**: 2026-03-31
- **Risk Level**: 🔴 **CRITICAL** - Can create real charges

#### Stripe Webhook Secret (Staging)
- **Name**: `STRIPE_WEBHOOK_SECRET_STAGING` (if used)
- **Location**: Supabase Edge Function secrets
- **Type**: Webhook signing secret
- **Purpose**: Verify Stripe webhook requests
- **Access**: Same as other Stripe secrets
- **Rotation**: When webhook endpoint is recreated
- **Last Rotated**: N/A
- **Next Rotation**: When webhook endpoint changes
- **Risk Level**: 🟠 **MEDIUM** - Prevents webhook spoofing

#### Stripe Webhook Secret (Production)
- **Name**: `STRIPE_WEBHOOK_SECRET` (if used)
- **Location**: Supabase Edge Function secrets
- **Type**: Webhook signing secret
- **Purpose**: Verify Stripe webhook requests
- **Access**: Same as other Stripe secrets
- **Rotation**: When webhook endpoint is recreated
- **Last Rotated**: N/A
- **Next Rotation**: When webhook endpoint changes
- **Risk Level**: 🟠 **MEDIUM** - Prevents webhook spoofing

#### Stripe Publishable Key (Public)
- **Name**: `STRIPE_PUBLISHABLE_KEY` (in iOS app)
- **Location**: iOS app code (if used)
- **Type**: Public key (safe to expose)
- **Purpose**: Client-side Stripe operations (PaymentSheet, Apple Pay)
- **Access**: Public (embedded in app)
- **Rotation**: N/A (public key, safe to expose)
- **Risk Level**: 🟢 **LOW** - Public key, cannot create charges

---

### 3. Apple Secrets

#### Apple Sign In Configuration
- **Name**: Apple Developer credentials
- **Location**: Apple Developer account
- **Type**: OAuth client ID and secret
- **Purpose**: Apple Sign In authentication
- **Access**: 
  - Configured in Supabase Dashboard → Authentication → Providers → Apple
  - Never stored in code
- **Rotation**: When Apple Developer account credentials change
- **Last Rotated**: N/A
- **Next Rotation**: As needed
- **Risk Level**: 🟠 **MEDIUM** - Authentication provider

---

### 4. iOS App Secrets

#### Supabase Auth Tokens
- **Name**: `supabase.auth.token`, `supabase.auth.refresh_token`
- **Location**: iOS Keychain (via `KeychainManager`)
- **Type**: JWT tokens (user session)
- **Purpose**: User authentication
- **Access**: 
  - Stored securely in iOS Keychain
  - Encrypted by iOS
  - Never stored in UserDefaults (migrated)
- **Rotation**: Automatically refreshed by Supabase SDK
- **Last Rotated**: On each token refresh
- **Next Rotation**: Automatic (expires after 1 hour, refreshed automatically)
- **Risk Level**: 🟠 **MEDIUM** - User session access

---

## Secrets Verification

### ✅ Secrets NOT in Code

All secrets are stored in Supabase Edge Function secrets or iOS Keychain. None are hardcoded in source code.

**Verification Method**: 
- ✅ `check_secrets.sh` script scans for common secret patterns
- ✅ Git pre-commit hook prevents secret commits
- ✅ Manual code review confirms no hardcoded secrets

### ✅ Secrets NOT in Git History

**Verification Method**:
- ✅ `.env` files are gitignored
- ✅ `check_secrets.sh` scans staged files
- ⚠️ Git history should be audited (see "Next Steps")

---

## Secret Storage Locations

### Supabase Edge Function Secrets
- **Location**: Supabase Dashboard → Project Settings → Edge Functions → Secrets
- **Access**: Project owners and admins only
- **Secrets Stored**:
  - `STAGING_SUPABASE_SECRET_KEY` (full database access, bypasses RLS)
  - `PRODUCTION_SUPABASE_SECRET_KEY` (full database access, bypasses RLS)
  - `STRIPE_SECRET_KEY_TEST`
  - `STRIPE_SECRET_KEY`
  - `SUPABASE_URL` (environment variable, not secret)

### iOS Keychain
- **Location**: iOS device Keychain (encrypted by iOS)
- **Access**: App only (via `KeychainManager`)
- **Secrets Stored**:
  - `supabase.auth.token`
  - `supabase.auth.refresh_token`
  - `supabase.auth.session`

### Apple Developer Account
- **Location**: Apple Developer portal
- **Access**: Apple Developer account holders
- **Secrets Stored**:
  - Apple Sign In OAuth credentials

---

## Secret Rotation Plan

### Quarterly Rotation (Recommended)

**Schedule**: Every 3 months (Q1, Q2, Q3, Q4)

**Secrets to Rotate**:
1. `STAGING_SUPABASE_SECRET_KEY`
2. `PRODUCTION_SUPABASE_SECRET_KEY`
3. `STRIPE_SECRET_KEY_TEST`
4. `STRIPE_SECRET_KEY`

**Note**: When rotating Supabase secret keys, rotate them in Supabase Dashboard → Settings → API. In Supabase's UI, this key is labeled "Service Role Key", but we store it as `STAGING_SUPABASE_SECRET_KEY` or `PRODUCTION_SUPABASE_SECRET_KEY` in Edge Function secrets for clarity.

**Rotation Process**:
1. Generate new secret in source system (Supabase Dashboard, Stripe Dashboard)
2. Update Supabase Edge Function secrets
3. Test Edge Functions with new secrets
4. Deploy Edge Functions
5. Verify all functions work correctly
6. Document rotation date
7. Mark old secrets for deletion (after 30-day grace period)

**Rotation Checklist**:
- [ ] Generate new secrets
- [ ] Update Supabase Edge Function secrets
- [ ] Test all Edge Functions
- [ ] Deploy Edge Functions
- [ ] Verify payment processing works
- [ ] Verify authentication works
- [ ] Document rotation date
- [ ] Schedule next rotation

### Immediate Rotation (If Compromised)

**Trigger**: Security incident, suspected compromise, or key exposure

**Process**:
1. **Immediately** rotate all affected secrets
2. Revoke old secrets in source systems
3. Update Edge Function secrets
4. Deploy Edge Functions immediately
5. Monitor for unauthorized access
6. Document incident
7. Review security practices

**Incident Response Checklist**:
- [ ] Identify compromised secrets
- [ ] Rotate all affected secrets immediately
- [ ] Revoke old secrets
- [ ] Update Edge Function secrets
- [ ] Deploy Edge Functions
- [ ] Monitor for unauthorized access
- [ ] Document incident
- [ ] Review security practices

---

## Secret Access Controls

### Who Can Access Secrets?

1. **Supabase Edge Function Secrets**:
   - Project owners (via Supabase Dashboard)
   - Project admins (via Supabase Dashboard)
   - Edge Functions (at runtime, via `Deno.env.get()`)

2. **iOS Keychain Secrets**:
   - iOS app (via `KeychainManager`)
   - User's device (encrypted by iOS)

3. **Apple Developer Secrets**:
   - Apple Developer account holders
   - Supabase (for OAuth configuration)

### Access Logging

- ✅ Supabase Dashboard logs admin access
- ✅ Stripe Dashboard logs API key usage
- ⚠️ Edge Function secret access not logged (to be implemented)

---

## Secret Security Measures

1. **No Hardcoded Secrets**: All secrets stored in secure locations
2. **Environment-Specific Secrets**: Separate secrets for staging and production
3. **Keychain Storage**: iOS tokens stored in encrypted Keychain
4. **RLS Protection**: Database access protected by Row Level Security
5. **Rate Limiting**: API endpoints rate-limited to prevent abuse
6. **Input Validation**: All inputs validated before processing
7. **Secrets Scanning**: Automated scanning prevents secret commits

---

## Compliance Status

- ✅ **No Secrets in Code**: Verified via `check_secrets.sh`
- ✅ **Secrets in Secure Storage**: All secrets in Supabase secrets or Keychain
- ✅ **Environment Separation**: Separate secrets for staging/production
- ⚠️ **Rotation Schedule**: Needs to be implemented
- ⚠️ **Access Logging**: Needs to be enhanced
- ⚠️ **Git History Audit**: Needs to be performed

---

## Next Steps

1. ✅ Complete secrets inventory (this document)
2. ⏳ Set up quarterly rotation schedule
3. ⏳ Audit git history for accidentally committed secrets
4. ⏳ Implement secret expiration alerts
5. ⏳ Enhance access logging
6. ⏳ Create incident response playbook
7. ⏳ Regular review (quarterly) of secrets inventory

---

## Rotation Schedule

### 2026 Q1 (January - March)
- **Scheduled Rotation**: 2026-03-31
- **Secrets to Rotate**: All Supabase and Stripe keys
- **Status**: ⏳ Pending

### 2026 Q2 (April - June)
- **Scheduled Rotation**: 2026-06-30
- **Secrets to Rotate**: All Supabase and Stripe keys
- **Status**: ⏳ Pending

### 2026 Q3 (July - September)
- **Scheduled Rotation**: 2026-09-30
- **Secrets to Rotate**: All Supabase and Stripe keys
- **Status**: ⏳ Pending

### 2026 Q4 (October - December)
- **Scheduled Rotation**: 2026-12-31
- **Secrets to Rotate**: All Supabase and Stripe keys
- **Status**: ⏳ Pending

---

**Document Owner**: Security Team  
**Review Frequency**: Quarterly  
**Last Review Date**: 2025-12-31  
**Next Review Date**: 2026-03-31

