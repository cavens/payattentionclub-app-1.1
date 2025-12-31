# Security & Privacy Implementation Plan

**Status**: 📋 Planning Phase  
**Priority**: High  
**Last Updated**: 2025-12-15

> ⚠️ **IMPORTANT NOTE**: This security plan may not be fully implemented yet. When starting a new chat conversation, review this document to understand what security measures are planned vs. what has actually been implemented. Check the implementation status of each phase before assuming features are in place.

---

## Executive Summary

This document outlines the security and privacy measures needed to protect the PayAttentionClub application, user data, and infrastructure. The plan focuses on **security** (preventing unauthorized access and data breaches) while also addressing **privacy** (user data protection and compliance).

---

## Current Security Posture

### ✅ Already Implemented

1. **Secrets Management**
   - ✅ `check_secrets.sh` script scans for exposed secrets
   - ✅ Git pre-commit and pre-push hooks prevent secret commits
   - ✅ `.env` file is gitignored
   - ✅ Deployment scripts check for secrets before deploying

2. **Authentication**
   - ✅ Supabase Auth with Apple Sign In
   - ✅ JWT-based authentication
   - ✅ Service role key protected (not in code)

3. **Infrastructure**
   - ✅ HTTPS/TLS (Supabase handles this)
   - ✅ Separate staging and production environments
   - ✅ Environment-specific configuration

### ⚠️ Gaps Identified

1. **Database Security**
   - ❌ Row Level Security (RLS) policies not verified
   - ❌ Database access controls need review
   - ❌ RPC function security (SECURITY DEFINER) needs audit

2. **API Security**
   - ❌ Edge Function authorization checks inconsistent
   - ❌ Rate limiting not implemented
   - ❌ Input validation minimal
   - ❌ CORS policies need review

3. **Data Protection**
   - ❌ Encryption at rest not verified
   - ❌ PII handling not documented
   - ❌ Data retention policies missing

4. **Monitoring & Incident Response**
   - ❌ Security logging not implemented
   - ❌ Alerting for suspicious activity missing
   - ❌ Incident response plan not defined

5. **Privacy & Compliance**
   - ❌ Privacy policy not implemented
   - ❌ GDPR compliance not verified
   - ❌ Data deletion/user rights not automated

6. **Repository Security**
   - ❌ GitHub repository visibility not verified (should be private)
   - ❌ Git history may contain secrets (needs audit)

---

## Security Implementation Plan

### Phase 1: Database Security (Critical) 🔴

**Priority**: **HIGH** - Protects user data at the source

#### 1.1 Row Level Security (RLS) Audit & Implementation

**Tasks:**
- [ ] Audit all tables for RLS policies
- [ ] Verify users can only access their own data
- [ ] Implement RLS policies for:
  - `commitments` - users can only see their own
  - `daily_usage` - users can only see their own
  - `user_week_penalties` - users can only see their own
  - `payments` - users can only see their own
  - `users` - users can only see their own row
- [ ] Test RLS policies with authenticated and anon roles
- [ ] Document RLS policies

**Risk if not done**: Users could access other users' data

#### 1.2 RPC Function Security Review

**Tasks:**
- [ ] Audit all RPC functions using `SECURITY DEFINER`
- [ ] Verify functions properly validate user identity
- [ ] Ensure functions don't bypass RLS inappropriately
- [ ] Review function permissions (GRANT/REVOKE)
- [ ] Document security model for each function

**Risk if not done**: Privilege escalation, unauthorized data access

#### 1.3 Database Access Controls

**Tasks:**
- [ ] Verify service role key is only used server-side
- [ ] Review database user roles and permissions
- [ ] Ensure anon/authenticated roles have minimal permissions
- [ ] Document database access model

**Risk if not done**: Unauthorized database access

---

### Phase 2: API Security (Critical) 🔴

**Priority**: **HIGH** - Protects API endpoints

#### 2.1 Edge Function Authorization

**Tasks:**
- [ ] Audit all Edge Functions for authorization checks
- [ ] Ensure all functions verify JWT tokens
- [ ] Implement consistent authorization pattern:
  ```typescript
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return unauthorized();
  // Verify JWT and extract user ID
  ```
- [ ] Add user context validation (user can only access their data)
- [ ] Document authorization requirements

**Functions to review:**
- `billing-status`
- `bright-processor`
- `bright-service`
- `quick-handler`
- `rapid-service`
- `super-service`
- `weekly-close`
- `stripe-webhook`

**Risk if not done**: Unauthorized API access, data breaches

#### 2.2 Input Validation & Sanitization

**Tasks:**
- [ ] Add input validation to all Edge Functions
- [ ] Validate data types, ranges, formats
- [ ] Sanitize user inputs (prevent SQL injection, XSS)
- [ ] Implement request size limits
- [ ] Add validation for:
  - User IDs (UUID format)
  - Dates (valid date ranges)
  - Amounts (positive numbers, reasonable limits)
  - Email addresses (format validation)

**Risk if not done**: Injection attacks, data corruption

#### 2.3 Rate Limiting

**Tasks:**
- [ ] Review Supabase built-in rate limiting settings
- [ ] Configure rate limits per user/IP:
  - Authentication endpoints: 5 requests/minute
  - RPC calls: 60 requests/minute
  - Payment endpoints: 10 requests/minute
- [ ] Use Supabase Dashboard → Settings → API → Rate Limiting
- [ ] Add custom rate limiting in Edge Functions (if needed beyond Supabase defaults)
- [ ] Add rate limit headers to responses
- [ ] Document rate limits

**Note**: Supabase provides built-in rate limiting. We need to configure it appropriately.

**Risk if not done**: DDoS attacks, abuse, cost overruns

#### 2.4 CORS & Headers

**Tasks:**
- [ ] Review and tighten CORS policies
- [ ] Only allow specific origins (iOS app bundle IDs)
- [ ] Add security headers:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security`
- [ ] Remove unnecessary CORS headers

**Risk if not done**: Cross-origin attacks, clickjacking

---

### Phase 3: Data Protection (High) 🟠

**Priority**: **HIGH** - Protects sensitive user data

#### 3.1 Encryption

**Tasks:**
- [x] ✅ Supabase encryption at rest (enabled by default - verified)
- [x] ✅ Encryption in transit (HTTPS/TLS - Supabase managed)
- [ ] Review sensitive data fields:
  - Email addresses
  - Stripe customer IDs
  - Payment information
- [ ] Consider field-level encryption for PII (if needed - likely not required)

**Note**: Supabase handles infrastructure encryption. We focus on application-level data protection.

**Risk if not done**: Data exposure if database is compromised (mitigated by Supabase)

#### 3.2 PII Handling

**Tasks:**
- [ ] Document all PII collected:
  - Email addresses
  - Apple ID (pseudonymous)
  - Usage data (app names, timestamps)
  - Payment data (handled by Stripe)
- [ ] Implement data minimization (only collect what's needed)
- [ ] Add PII tagging to database schema
- [ ] Document data flow and storage

**Risk if not done**: Privacy violations, compliance issues

#### 3.3 Secrets Management

**Tasks:**
- [ ] Review all secrets in use:
  - Supabase service role keys
  - Stripe API keys
  - Loops.so API keys
  - Webhook secrets
- [ ] Verify secrets are in Supabase Edge Function secrets (not code)
- [ ] Rotate secrets periodically (quarterly)
- [ ] Document secret rotation process
- [ ] Implement secret expiration alerts

**Risk if not done**: Secret exposure, unauthorized access

---

### Phase 4: Monitoring & Incident Response (Medium) 🟡

**Priority**: **MEDIUM** - Enables detection and response

#### 4.1 Security Logging

**Tasks:**
- [ ] Implement security event logging:
  - Failed authentication attempts
  - Unauthorized API access
  - Rate limit violations
  - Suspicious patterns (multiple failed requests)
- [ ] Log to Supabase logs or external service
- [ ] Retain logs for 90 days minimum
- [ ] Add log aggregation and search

**Risk if not done**: Can't detect or investigate security incidents

#### 4.2 Alerting

**Tasks:**
- [ ] Set up alerts for:
  - Multiple failed auth attempts
  - Unusual API usage patterns
  - Rate limit violations
  - Database access anomalies
- [ ] Configure alert channels (email, Slack, etc.)
- [ ] Define alert severity levels
- [ ] Test alerting system

**Risk if not done**: Delayed response to security incidents

#### 4.3 Incident Response Plan

**Tasks:**
- [ ] Document incident response procedures
- [ ] Define roles and responsibilities
- [ ] Create runbook for common incidents:
  - Data breach
  - Unauthorized access
  - DDoS attack
  - Secret exposure
- [ ] Define communication plan (users, stakeholders)
- [ ] Practice incident response (tabletop exercise)

**Risk if not done**: Chaotic response to security incidents

---

### Phase 5: Privacy & Compliance (Medium) 🟡

**Priority**: **MEDIUM** - Legal and ethical requirements

#### 5.1 Privacy Policy

**Tasks:**
- [ ] Create privacy policy covering:
  - Data collected
  - How data is used
  - Data sharing (Stripe, Loops.so)
  - User rights (access, deletion, portability)
  - Data retention
- [ ] Display privacy policy in app
- [ ] Get legal review
- [ ] Update as needed

**Risk if not done**: Legal liability, user trust issues

#### 5.2 GDPR Compliance

**Tasks:**
- [ ] Implement user data export (GDPR Article 15)
- [ ] Implement user data deletion (GDPR Article 17)
- [ ] Add "Right to be forgotten" functionality
- [ ] Document data processing activities
- [ ] Verify lawful basis for processing
- [ ] Add consent mechanisms (if needed)

**Risk if not done**: GDPR fines, legal issues

#### 5.3 Data Retention

**Tasks:**
- [ ] Define data retention policies:
  - Active users: Keep all data
  - Inactive users: Delete after 2 years
  - Deleted accounts: Delete immediately
- [ ] Implement automated data cleanup
- [ ] Document retention periods
- [ ] Add data retention to privacy policy

**Risk if not done**: Unnecessary data storage, compliance issues

---

### Phase 7: iOS Frontend Security (High) 🟠

**Priority**: **HIGH** - Protects client-side data and communication

#### 7.1 Secure Credential Storage

**Tasks:**
- [ ] Audit current credential storage:
  - JWT tokens - Where are they stored? (UserDefaults vs Keychain)
  - Supabase session - How is it persisted?
  - API keys - Are any hardcoded? (should be in Config.swift only)
- [ ] Migrate sensitive data to Keychain:
  - Use Keychain Services for JWT tokens
  - Use Keychain for any API keys (if needed)
  - Verify Supabase client uses secure storage
- [ ] Review `Config.swift` - Ensure no secrets hardcoded
- [ ] Test credential persistence and retrieval

**Current Status**: Need to verify if Supabase client uses Keychain automatically

**Risk if not done**: Credentials stored insecurely, accessible if device compromised

#### 7.2 Secure Communication

**Tasks:**
- [x] ✅ App Transport Security (ATS) - Enforced by iOS by default
- [ ] Verify all API endpoints use HTTPS (Supabase does)
- [ ] Consider certificate pinning for Supabase:
  - Pin Supabase SSL certificates
  - Prevent man-in-the-middle attacks
  - Use `URLSession` with certificate pinning
- [ ] Review network security settings in `Info.plist`
- [ ] Test with network proxy to verify HTTPS enforcement

**Risk if not done**: Man-in-the-middle attacks (mitigated by ATS, but pinning adds extra layer)

#### 7.3 Input Validation & Sanitization

**Tasks:**
- [ ] Validate all user inputs before sending to backend:
  - Commitment amounts (positive numbers, reasonable limits)
  - Time limits (valid ranges)
  - App selections (valid format)
- [ ] Sanitize data before display:
  - Prevent XSS if displaying user-generated content
  - Escape special characters
- [ ] Add input validation in Swift code
- [ ] Test with malicious inputs

**Risk if not done**: Invalid data sent to backend, potential injection attacks

#### 7.4 Token Management

**Tasks:**
- [ ] Review JWT token handling:
  - How tokens are stored (Keychain vs UserDefaults)
  - Token refresh mechanism
  - Token expiration handling
- [ ] Implement secure token refresh:
  - Automatic refresh before expiration
  - Secure storage of refresh tokens
  - Handle refresh failures gracefully
- [ ] Clear tokens on logout
- [ ] Test token lifecycle

**Risk if not done**: Token exposure, unauthorized access

#### 7.5 App Group Security

**Tasks:**
- [ ] Review App Group usage:
  - What data is shared via App Group?
  - Is sensitive data in App Group?
  - How is App Group data protected?
- [ ] Verify App Group entitlements are correct
- [ ] Ensure App Group data is cleared when app is deleted
- [ ] Document App Group security model

**Risk if not done**: Data leakage between app and extensions

#### 7.6 Sensitive Data Handling

**Tasks:**
- [ ] Audit logging and debugging:
  - Remove sensitive data from logs
  - Don't log JWT tokens, API keys, user emails
  - Use secure logging (if needed)
- [ ] Clear sensitive data from memory:
  - Clear tokens when done
  - Overwrite sensitive variables
- [ ] Review what data is stored locally:
  - UserDefaults - Only non-sensitive data
  - Core Data - Encrypted if sensitive
  - Files - Use Data Protection classes
- [ ] Test data clearing on app deletion

**Risk if not done**: Sensitive data in logs, memory dumps, or local storage

#### 7.7 Code Security

**Tasks:**
- [ ] Review for hardcoded secrets:
  - API keys in code (should only be publishable keys)
  - Service role keys (should NEVER be in app)
  - Test credentials (remove before production)
- [ ] Obfuscation (if needed):
  - Consider code obfuscation for sensitive logic
  - Usually not needed for most apps
- [ ] Review entitlements:
  - Only request necessary permissions
  - Document why each entitlement is needed
- [ ] Test with security scanning tools:
  - Run Semgrep on Swift code
  - Check for common vulnerabilities

**Risk if not done**: Secrets in compiled app, excessive permissions

---

### Phase 6: Automated Security Scanning (High) 🟠

**Priority**: **HIGH** - Continuous security monitoring

#### 6.1 Static Application Security Testing (SAST)

**Tasks:**
- [ ] Set up automated code scanning:
  - **GitHub Advanced Security** (if available) - scans code for vulnerabilities
  - **Semgrep** - open-source SAST tool for Swift/TypeScript
  - **CodeQL** (GitHub) - semantic code analysis
- [ ] Integrate into CI/CD pipeline (when implemented)
- [ ] Scan on every commit/PR
- [ ] Configure to scan:
  - Swift code (iOS app)
  - TypeScript/Deno code (Edge Functions)
  - SQL files (SQL injection patterns)
- [ ] Set up alerts for high-severity findings

**Tools to consider:**
- Semgrep (free, open-source)
- GitHub Code Scanning (if on GitHub)
- SonarQube (if self-hosted CI/CD)

**Risk if not done**: Vulnerabilities go undetected until manual review

#### 6.2 Dependency Scanning

**Tasks:**
- [ ] Set up dependency vulnerability scanning:
  - **Swift Package Manager** - Check for vulnerable dependencies
  - **npm/Deno dependencies** - Scan Edge Function dependencies
  - **CocoaPods** (if used) - Scan iOS dependencies
- [ ] Use tools:
  - **Dependabot** (GitHub) - Automated dependency updates
  - **Snyk** - Dependency vulnerability scanning
  - **npm audit** / **deno audit** - Built-in Deno/npm scanning
- [ ] Configure automated PRs for security updates
- [ ] Set up alerts for critical vulnerabilities

**Risk if not done**: Vulnerable dependencies in production

#### 6.3 Secrets Scanning (Enhanced)

**Tasks:**
- [x] ✅ Basic secrets scanning (`check_secrets.sh`)
- [ ] Enhance with additional tools:
  - **GitGuardian** - Advanced secrets detection
  - **TruffleHog** - Scans git history for secrets
  - **GitHub Secret Scanning** - Built-in if on GitHub
- [ ] Scan git history for accidentally committed secrets
- [ ] Set up automated alerts
- [ ] Regular audits (monthly)

**Risk if not done**: Secrets in git history go undetected

#### 6.4 Local Development Security Checks

**Tasks:**
- [ ] Create pre-commit hook enhancements:
  - Run `check_secrets.sh` (already done)
  - Run dependency audit (if applicable)
  - Run basic SAST scan (Semgrep quick scan)
- [ ] Add to `package.json` or similar:
  ```json
  "scripts": {
    "security:check": "check_secrets.sh && deno audit && semgrep --config=auto"
  }
  ```
- [ ] Document local security checks in README

**Risk if not done**: Vulnerabilities committed before CI/CD catches them

---

## Implementation Priority

### 🔴 Critical (Do First)
1. **Phase 1: Database Security** - RLS policies, RPC security
2. **Phase 2: API Security** - Authorization, input validation

### 🟠 High (Do Next)
3. **Phase 3: Data Protection** - PII handling (encryption handled by Supabase)
4. **Phase 7: iOS Frontend Security** - Credential storage, secure communication, token management
5. **Phase 6: Automated Security Scanning** - SAST, dependency scanning

### 🟡 Medium (Do Soon)
6. **Phase 4: Monitoring** - Logging, alerting, incident response
7. **Phase 5: Privacy** - Privacy policy, GDPR compliance

---

## Success Criteria

### Phase 1 Complete When:
- ✅ All tables have RLS policies
- ✅ Users can only access their own data (tested)
- ✅ All RPC functions reviewed and secured

### Phase 2 Complete When:
- ✅ All Edge Functions verify authorization
- ✅ Input validation on all endpoints
- ✅ Rate limiting implemented

### Phase 3 Complete When:
- ✅ Encryption verified
- ✅ PII documented and protected
- ✅ Secrets properly managed

### Phase 4 Complete When:
- ✅ Security logging operational
- ✅ Alerts configured and tested
- ✅ Incident response plan documented

### Phase 5 Complete When:
- ✅ Privacy policy published
- ✅ GDPR rights implemented
- ✅ Data retention automated

---

---

## Essential Implementation Plan (80/20 Rule)

**Focus**: Critical security items that provide 80% of protection  
**Estimated Time**: 2-3 days (vs 11-17 days for full plan)

---

## Step-by-Step Implementation Guide

### Day 1: Quick Wins (~6 hours)

#### Task 0: Make GitHub Repository Private (5 min)

**Step 0.1: Verify Repository Visibility** (2 min)
1. Go to GitHub repository: `https://github.com/cavens/payattentionclub-app-1.1`
2. Check if repository is currently public or private
3. If public, proceed to make it private

**Step 0.2: Make Repository Private** (3 min)
1. Go to repository Settings → General
2. Scroll down to "Danger Zone"
3. Click "Change visibility"
4. Select "Make private"
5. Confirm by typing the repository name
6. Click "I understand, change repository visibility"

**Why this matters:**
- Public repositories expose all code and commit history
- Even if secrets are removed, they may exist in git history
- Reduces attack surface
- Prevents code analysis by malicious actors

**Note**: If you need to keep it public temporarily (e.g., for open source), ensure:
- All secrets are removed from history (use `remove_secrets_from_history.sh`)
- No sensitive data in code
- Consider using GitHub's secret scanning features

---

#### Task 1: Verify and Implement RLS Policies (2 hours)

**Step 1.1: Check Current RLS Status** (15 min)
1. Open Supabase Dashboard → SQL Editor
2. Run this query to see which tables have RLS enabled:
   ```sql
   SELECT tablename, rowsecurity 
   FROM pg_tables 
   WHERE schemaname = 'public'
   ORDER BY tablename;
   ```
3. Run this to see existing policies:
   ```sql
   SELECT tablename, policyname, cmd, qual
   FROM pg_policies 
   WHERE schemaname = 'public'
   ORDER BY tablename, policyname;
   ```
4. Document findings in a text file

**Step 1.2: Identify Critical Tables** (5 min)
Critical tables that MUST have RLS:
- `users` - User profile data
- `commitments` - User commitments
- `daily_usage` - Usage tracking data
- `user_week_penalties` - Penalty calculations
- `payments` - Payment records
- `weekly_pools` - Pool data (may need special handling)

**Step 1.3: Create RLS Policies** (60 min)
For each critical table missing RLS:

1. **Enable RLS**:
   ```sql
   ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.commitments ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.daily_usage ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.user_week_penalties ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
   ```

2. **Create policies** (users can only see their own data):
   ```sql
   -- Users table
   CREATE POLICY "Users see own profile" ON public.users
     FOR ALL USING (auth.uid() = id);
   
   -- Commitments table
   CREATE POLICY "Users see own commitments" ON public.commitments
     FOR ALL USING (auth.uid() = user_id);
   
   -- Daily usage table
   CREATE POLICY "Users see own usage" ON public.daily_usage
     FOR ALL USING (auth.uid() = user_id);
   
   -- User week penalties table
   CREATE POLICY "Users see own penalties" ON public.user_week_penalties
     FOR ALL USING (auth.uid() = user_id);
   
   -- Payments table
   CREATE POLICY "Users see own payments" ON public.payments
     FOR ALL USING (auth.uid() = user_id);
   ```

3. **Special case: weekly_pools** (if users need read access):
   ```sql
   -- Users can read all pools (for transparency)
   CREATE POLICY "Users can read pools" ON public.weekly_pools
     FOR SELECT USING (true);
   
   -- Only service role can insert/update
   -- (No policy = only service role can modify)
   ```

**Step 1.4: Test RLS Policies** (30 min)
1. Create a test SQL script:
   ```sql
   -- Set session to test user
   SET request.jwt.claim.sub = 'test-user-uuid-here';
   
   -- Try to select from each table
   SELECT * FROM public.commitments LIMIT 1;
   SELECT * FROM public.daily_usage LIMIT 1;
   -- etc.
   ```
2. Verify users can only see their own data
3. Test with service role key (should see all data)
4. Document test results

**Step 1.5: Create Migration File** (10 min)
1. Create file: `supabase/migrations/YYYYMMDDHHMMSS_add_rls_policies.sql`
2. Copy all ALTER TABLE and CREATE POLICY statements
3. Add comments explaining each policy
4. Commit to git

---

#### Task 2: Add Authorization to Edge Functions (3 hours)

**Step 2.1: Identify Functions to Secure** (15 min)
1. List all Edge Functions:
   ```bash
   ls supabase/functions/
   ```
2. Priority functions (user-facing):
   - `billing-status`
   - `super-service` (create-commitment)
   - `rapid-service`
   - `bright-service`
   - `bright-processor`
   - `quick-handler`
3. Lower priority (internal/admin):
   - `weekly-close` (uses service role)
   - `stripe-webhook` (uses webhook secret)

**Step 2.2: Create Authorization Helper** (30 min)
1. Create shared utility file: `supabase/functions/_shared/auth.ts`
   ```typescript
   export function verifyAuth(req: Request): { userId: string } | null {
     const authHeader = req.headers.get('Authorization');
     if (!authHeader || !authHeader.startsWith('Bearer ')) {
       return null;
     }
     
     const token = authHeader.substring(7);
     // Verify JWT token with Supabase
     // Extract user ID from token
     // Return { userId } or null if invalid
   }
   
   export function requireAuth(req: Request): { userId: string } {
     const auth = verifyAuth(req);
     if (!auth) {
       throw new Response('Unauthorized', { status: 401 });
     }
     return auth;
   }
   ```

2. Or use Supabase client to verify:
   ```typescript
   import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
   
   export async function verifyAuth(req: Request) {
     const authHeader = req.headers.get('Authorization');
     if (!authHeader) return null;
     
     const supabase = createClient(
       Deno.env.get('SUPABASE_URL') ?? '',
       Deno.env.get('SUPABASE_ANON_KEY') ?? '',
       { global: { headers: { Authorization: authHeader } } }
     );
     
     const { data: { user }, error } = await supabase.auth.getUser();
     if (error || !user) return null;
     
     return { userId: user.id };
   }
   ```

**Step 2.3: Update Each Function** (2 hours)
For each priority function:

1. **billing-status**:
   ```typescript
   // At start of function
   const auth = await verifyAuth(req);
   if (!auth) {
     return new Response('Unauthorized', { status: 401 });
   }
   
   // Use auth.userId in queries
   ```

2. **super-service** (create-commitment):
   ```typescript
   // At start of function
   const auth = await verifyAuth(req);
   if (!auth) {
     return new Response('Unauthorized', { status: 401 });
   }
   
   // Verify userId in request body matches auth.userId
   const body = await req.json();
   if (body.userId !== auth.userId) {
     return new Response('Forbidden', { status: 403 });
   }
   ```

3. **rapid-service**:
   ```typescript
   // Same pattern as above
   ```

4. **bright-service** and **bright-processor**:
   ```typescript
   // Add auth check
   ```

5. **quick-handler** (settlement-reconcile):
   ```typescript
   // This may need service role, verify requirements
   ```

**Step 2.4: Test Authorization** (15 min)
1. Test each function without Authorization header → should return 401
2. Test with invalid token → should return 401
3. Test with valid token → should work
4. Document test results

---

#### Task 3: Migrate iOS Credentials to Keychain (2 hours)

**Step 3.1: Review Current Storage** (15 min)
1. Open `BackendClient.swift`
2. Find where credentials are stored (likely `UserDefaultsLocalStorage`)
3. Search for `UserDefaults` usage related to auth
4. Document current implementation

**Step 3.2: Create Keychain Helper** (45 min)
1. Create new file: `Utilities/KeychainManager.swift`
   ```swift
   import Foundation
   import Security
   
   class KeychainManager {
     static let shared = KeychainManager()
     
     private let service = "com.payattentionclub.app"
     
     func save(key: String, value: String) -> Bool {
       // Implementation to save to Keychain
     }
     
     func get(key: String) -> String? {
       // Implementation to read from Keychain
     }
     
     func delete(key: String) -> Bool {
       // Implementation to delete from Keychain
     }
   }
   ```

2. Use `kSecClassGenericPassword` for JWT tokens
3. Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for security

**Step 3.3: Update BackendClient** (45 min)
1. Replace `UserDefaultsLocalStorage` with `KeychainManager`
2. Update token storage:
   ```swift
   // Old:
   UserDefaults.standard.set(token, forKey: "supabase_token")
   
   // New:
   KeychainManager.shared.save(key: "supabase_token", value: token)
   ```
3. Update token retrieval:
   ```swift
   // Old:
   let token = UserDefaults.standard.string(forKey: "supabase_token")
   
   // New:
   let token = KeychainManager.shared.get(key: "supabase_token")
   ```

**Step 3.4: Test Keychain Migration** (15 min)
1. Build and run app
2. Sign in → verify token is saved to Keychain
3. Close app → reopen → verify token is retrieved
4. Check Keychain Access app (macOS) to verify storage
5. Test logout → verify token is deleted

---

#### Task 4: Basic Input Validation (2 hours)

**Step 4.1: Create Validation Helper** (30 min)
1. Create: `supabase/functions/_shared/validation.ts`
   ```typescript
   export function validateUUID(value: any): string | null {
     const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
     if (typeof value !== 'string' || !uuidRegex.test(value)) {
       return null;
     }
     return value;
   }
   
   export function validatePositiveNumber(value: any, max?: number): number | null {
     const num = Number(value);
     if (isNaN(num) || num < 0) return null;
     if (max !== undefined && num > max) return null;
     return num;
   }
   
   export function validateDate(value: any): Date | null {
     const date = new Date(value);
     if (isNaN(date.getTime())) return null;
     return date;
   }
   ```

**Step 4.2: Add Validation to Functions** (1.5 hours)
For each Edge Function:

1. **super-service** (create-commitment):
   ```typescript
   const body = await req.json();
   
   // Validate user ID
   const userId = validateUUID(body.userId);
   if (!userId) {
     return new Response('Invalid user ID', { status: 400 });
   }
   
   // Validate amounts
   const limitMinutes = validatePositiveNumber(body.limitMinutes, 2520); // 42 hours max
   if (!limitMinutes) {
     return new Response('Invalid limit', { status: 400 });
   }
   
   const penaltyPerMinute = validatePositiveNumber(body.penaltyPerMinute, 5.0);
   if (!penaltyPerMinute) {
     return new Response('Invalid penalty rate', { status: 400 });
   }
   
   // Validate date
   const weekStartDate = validateDate(body.weekStartDate);
   if (!weekStartDate) {
     return new Response('Invalid date', { status: 400 });
   }
   ```

2. **rapid-service**:
   ```typescript
   // Validate sync data
   const userId = validateUUID(body.userId);
   const usageSeconds = validatePositiveNumber(body.usageSeconds, 86400 * 7); // Max 7 days
   // etc.
   ```

3. **billing-status**:
   ```typescript
   // Validate user ID from query params or body
   ```

**Step 4.3: Test Validation** (15 min)
1. Test with invalid UUID → should return 400
2. Test with negative numbers → should return 400
3. Test with invalid dates → should return 400
4. Test with valid data → should work
5. Document test results

---

### Day 2: Critical Items (~6 hours)

#### Task 5: Audit RPC Functions (3 hours)

**Step 5.1: List All RPC Functions** (30 min)
1. Run SQL query:
   ```sql
   SELECT 
     p.proname as function_name,
     pg_get_functiondef(p.oid) as definition
   FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
     AND p.prosecdef = true  -- SECURITY DEFINER functions
   ORDER BY p.proname;
   ```
2. Also check regular functions:
   ```sql
   SELECT 
     p.proname as function_name,
     p.prosecdef as is_security_definer
   FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
   ORDER BY p.proname;
   ```
3. Document all functions found

**Step 5.2: Review Each Function** (2 hours)
For each `SECURITY DEFINER` function:

1. **Check if it validates user identity**:
   - Should check `auth.uid()` or `request.jwt.claim.sub`
   - Should verify user has permission to access data
   - Should not allow cross-user data access

2. **Example review checklist**:
   ```sql
   -- ❌ BAD: No user validation
   CREATE FUNCTION get_user_data(user_id UUID) ...
   
   -- ✅ GOOD: Validates user
   CREATE FUNCTION get_user_data(user_id UUID) ...
   AS $$
   BEGIN
     IF auth.uid() != user_id THEN
       RAISE EXCEPTION 'Unauthorized';
     END IF;
     -- ... rest of function
   END;
   $$;
   ```

3. **Functions to prioritize**:
   - `rpc_create_commitment`
   - `rpc_sync_daily_usage`
   - `rpc_get_week_status`
   - `rpc_preview_max_charge`
   - Any function that modifies user data

**Step 5.3: Fix Insecure Functions** (30 min)
1. For each function missing validation:
   - Add `auth.uid()` check at start
   - Verify user can only access their own data
   - Test with different users
2. Create migration file with fixes
3. Document changes

---

#### Task 6: Configure Rate Limiting (1 hour)

**Step 6.1: Access Rate Limiting Settings** (5 min)
1. Go to Supabase Dashboard
2. Navigate to: Settings → API → Rate Limiting
3. Review current settings

**Step 6.2: Configure Limits** (30 min)
1. Set per-user limits:
   - **Authentication endpoints**: 5 requests/minute
   - **RPC calls**: 60 requests/minute
   - **Edge Functions**: 30 requests/minute
   - **Payment endpoints**: 10 requests/minute

2. Set per-IP limits (for unauthenticated):
   - **General API**: 100 requests/minute
   - **Authentication**: 10 requests/minute

3. Configure burst limits (if available):
   - Allow short bursts above limit
   - Prevent sustained abuse

**Step 6.3: Test Rate Limiting** (20 min)
1. Create test script to hit endpoint repeatedly
2. Verify rate limit is enforced
3. Check rate limit headers in response:
   - `X-RateLimit-Limit`
   - `X-RateLimit-Remaining`
   - `X-RateLimit-Reset`
4. Document limits configured

**Step 6.4: Document Configuration** (5 min)
1. Create file: `docs/RATE_LIMITING.md`
2. Document all limits set
3. Explain rationale for each limit
4. Add to git

---

#### Task 7: Document PII & Secrets (2 hours)

**Step 7.1: Inventory PII Collected** (45 min)
1. Review database schema:
   ```sql
   SELECT table_name, column_name, data_type
   FROM information_schema.columns
   WHERE table_schema = 'public'
   ORDER BY table_name, column_name;
   ```
2. Identify PII fields:
   - Email addresses (`users.email`)
   - Apple ID identifiers
   - Usage data (app names, timestamps)
   - Payment data (handled by Stripe, not stored)
3. Create document: `docs/PII_INVENTORY.md`
   ```markdown
   # PII Inventory
   
   ## Email Addresses
   - **Location**: `users.email`
   - **Source**: Apple Sign In (relay email)
   - **Purpose**: User identification, communication
   - **Retention**: While account active
   
   ## Apple ID
   - **Location**: `users.id` (Supabase Auth)
   - **Source**: Apple Sign In
   - **Purpose**: Authentication
   - **Retention**: While account active
   
   ## Usage Data
   - **Location**: `daily_usage` table
   - **Source**: DeviceActivity extension
   - **Purpose**: Track screen time
   - **Retention**: 90 days
   ```

**Step 7.2: Inventory Secrets** (45 min)
1. List all secrets in use:
   - Supabase service role key
   - Supabase anon key (public, OK)
   - Stripe secret keys (test + live)
   - Stripe webhook secrets
   - Loops.so API key (if used)
   - Any other API keys

2. Verify storage locations:
   ```bash
   # Check Supabase Edge Function secrets
   supabase secrets list
   
   # Check for secrets in code
   ./scripts/check_secrets.sh
   
   # Check .env files (should be gitignored)
   ls -la .env*
   ```

3. Create document: `docs/SECRETS_INVENTORY.md`
   ```markdown
   # Secrets Inventory
   
   ## Supabase Service Role Key
   - **Location**: Supabase Edge Function secrets
   - **Environment**: Staging + Production (separate)
   - **Access**: Service role only
   - **Rotation**: Quarterly
   - **Last Rotated**: [Date]
   
   ## Stripe Secret Keys
   - **Location**: Supabase Edge Function secrets
   - **Test Key**: `sk_test_...` (staging)
   - **Live Key**: `sk_live_...` (production)
   - **Rotation**: As needed
   - **Last Rotated**: [Date]
   ```

**Step 7.3: Verify No Secrets in Code** (30 min)
1. Run secrets check:
   ```bash
   ./scripts/check_secrets.sh
   ```
2. Search codebase for common patterns:
   ```bash
   grep -r "sk_live_" . --exclude-dir=node_modules
   grep -r "sk_test_" . --exclude-dir=node_modules
   grep -r "eyJ" . --exclude-dir=node_modules  # JWT tokens
   ```
3. If secrets found:
   - Rotate the secret immediately
   - Remove from code
   - Add to `.gitignore` if needed
   - Document in incident log

**Step 7.4: Create Secrets Rotation Plan** (15 min)
1. Document rotation process:
   - How to rotate each secret
   - Who has access
   - When to rotate
   - How to update all references
2. Add to `docs/SECRETS_ROTATION.md`
3. Set calendar reminders for quarterly rotation

---

### Day 3: Testing & Documentation (~4 hours)

#### Task 8: Test All Security Changes (2 hours)

**Step 8.1: Test RLS Policies** (30 min)
1. Create test script: `supabase/tests/test_rls_policies.sql`
2. Test as different users:
   - User A can see their own data
   - User A cannot see User B's data
   - Service role can see all data
3. Test each critical table
4. Document results

**Step 8.2: Test Edge Function Authorization** (30 min)
1. Test each function:
   - Without auth header → 401
   - With invalid token → 401
   - With valid token → works
   - With wrong user ID → 403 (if applicable)
2. Use curl or Postman
3. Document test results

**Step 8.3: Test Input Validation** (30 min)
1. Test each function with:
   - Invalid UUIDs
   - Negative numbers
   - Invalid dates
   - Missing required fields
   - Oversized inputs
2. Verify all return 400 errors
3. Document test results

**Step 8.4: Test iOS Keychain Migration** (30 min)
1. Test on physical device:
   - Sign in → verify token in Keychain
   - Close app → reopen → verify persistence
   - Sign out → verify token deleted
   - Test on app reinstall (token should persist)
2. Document test results

---

#### Task 9: Deploy to Staging (1 hour)

**Step 9.1: Create Migration Files** (15 min)
1. Consolidate all SQL changes into migration files:
   - `YYYYMMDDHHMMSS_add_rls_policies.sql`
   - `YYYYMMDDHHMMSS_fix_rpc_security.sql`
2. Test migrations locally if possible
3. Review all changes

**Step 9.2: Deploy to Staging** (30 min)
1. Run migrations in Supabase Dashboard → SQL Editor
2. Deploy Edge Functions:
   ```bash
   supabase functions deploy billing-status --project-ref <staging-ref>
   supabase functions deploy super-service --project-ref <staging-ref>
   # etc.
   ```
3. Verify deployments succeeded
4. Check function logs for errors

**Step 9.3: Smoke Test in Staging** (15 min)
1. Test critical user flows:
   - Sign in
   - Create commitment
   - Sync usage
   - View data
2. Verify no regressions
3. Check logs for errors

---

#### Task 10: Document Implementation (1 hour)

**Step 10.1: Update Security Plan** (20 min)
1. Mark completed items in `SECURITY_PLAN.md`
2. Update status from "Planning" to "Partially Implemented"
3. Add completion dates
4. Note any deviations from plan

**Step 10.2: Create Implementation Summary** (30 min)
1. Create: `docs/SECURITY_IMPLEMENTATION_SUMMARY.md`
   ```markdown
   # Security Implementation Summary
   
   **Date**: [Date]
   **Phase**: Essential Implementation (80/20)
   
   ## Completed Tasks
   
   ### Day 1
   - ✅ RLS policies implemented for all critical tables
   - ✅ Authorization added to 5 Edge Functions
   - ✅ iOS credentials migrated to Keychain
   - ✅ Basic input validation added
   
   ### Day 2
   - ✅ RPC functions audited and secured
   - ✅ Rate limiting configured
   - ✅ PII and secrets inventoried
   
   ### Day 3
   - ✅ All changes tested
   - ✅ Deployed to staging
   - ✅ Documentation updated
   
   ## Remaining Work
   - [ ] Deploy to production
   - [ ] Monitor for issues
   - [ ] Continue with Phase 4-7 (monitoring, privacy, etc.)
   ```

**Step 10.3: Update README** (10 min)
1. Add security section to main README
2. Link to security plan
3. Note what's implemented
4. Commit all changes

---

## Implementation Checklist

### Day 1: Quick Wins
- [ ] **Task 0**: Make GitHub repository private
  - [ ] Check current repository visibility
  - [ ] Change to private if public
  - [ ] Verify repository is now private
- [ ] **Task 1**: Verify RLS policies exist and work
  - [ ] Check current RLS status
  - [ ] Create policies for critical tables
  - [ ] Test policies
  - [ ] Create migration file
- [ ] **Task 2**: Add authorization checks to Edge Functions
  - [ ] Create auth helper utility
  - [ ] Update billing-status
  - [ ] Update super-service
  - [ ] Update rapid-service
  - [ ] Update bright-service
  - [ ] Test authorization
- [ ] **Task 3**: Migrate iOS credentials to Keychain
  - [ ] Review current storage
  - [ ] Create KeychainManager
  - [ ] Update BackendClient
  - [ ] Test migration
- [ ] **Task 4**: Add basic input validation
  - [ ] Create validation helper
  - [ ] Add validation to functions
  - [ ] Test validation

### Day 2: Critical Items
- [ ] **Task 5**: Audit and fix RPC function security
  - [ ] List all RPC functions
  - [ ] Review each function
  - [ ] Fix insecure functions
- [ ] **Task 6**: Configure rate limiting
  - [ ] Access settings
  - [ ] Configure limits
  - [ ] Test rate limiting
  - [ ] Document configuration
- [ ] **Task 7**: Document PII and secrets inventory
  - [ ] Inventory PII collected
  - [ ] Inventory secrets
  - [ ] Verify no secrets in code
  - [ ] Create rotation plan

### Day 3: Testing & Documentation
- [ ] **Task 8**: Test all security changes
  - [ ] Test RLS policies
  - [ ] Test Edge Function authorization
  - [ ] Test input validation
  - [ ] Test iOS Keychain migration
- [ ] **Task 9**: Deploy to staging
  - [ ] Create migration files
  - [ ] Deploy to staging
  - [ ] Smoke test
- [ ] **Task 10**: Document implementation
  - [ ] Update security plan
  - [ ] Create implementation summary
  - [ ] Update README

**Total**: 2-3 days for essential security

---

### Defer (Can Do Later)

- Certificate pinning (nice-to-have)
- Advanced monitoring/alerting (can add later)
- Privacy policy (needed before launch, not urgent now)
- GDPR automation (can be manual initially)
- Automated security scanning (can add to CI/CD later)

---

## Related Documentation

- `DEPLOYMENT_WORKFLOW.md` - Deployment security (secrets)
- `ARCHITECTURE.md` - System architecture
- `docs/KNOWN_ISSUES.md` - Known security issues

---

**Status**: Streamlined to essential items. Start with Quick Wins when ready.

