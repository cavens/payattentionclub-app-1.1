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

### Quick Wins (Day 1 - ~6 hours)

#### 1. Verify RLS Policies (2 hours)
```sql
-- Check which tables have RLS enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public';

-- Check existing policies
SELECT tablename, policyname 
FROM pg_policies 
WHERE schemaname = 'public';
```
**Action**: If RLS missing on critical tables (`commitments`, `daily_usage`, `payments`, `users`), add basic policies:
```sql
ALTER TABLE public.commitments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own data" ON public.commitments FOR ALL USING (auth.uid() = user_id);
```

#### 2. Add Authorization to Edge Functions (3 hours)
**Quick check**: Verify these functions check Authorization header:
- `billing-status`
- `super-service` (create-commitment)
- `rapid-service`

**Action**: Add simple auth check at start:
```typescript
const authHeader = req.headers.get('Authorization');
if (!authHeader) return new Response('Unauthorized', { status: 401 });
```

#### 3. Migrate iOS Credentials to Keychain (2 hours)
**Current**: `BackendClient.swift` uses `UserDefaultsLocalStorage`  
**Action**: Replace with Keychain-based storage (see Phase 7.2 in plan)

#### 4. Basic Input Validation (2 hours)
**Action**: Add validation to Edge Functions for:
- User IDs (must be UUID)
- Amounts (must be positive, reasonable limits)
- Dates (must be valid ISO format)

### Critical Items (Day 2 - ~6 hours)

#### 5. Audit RPC Functions (3 hours)
- List all `SECURITY DEFINER` functions
- Verify they validate `auth.uid()`
- Fix any that don't

#### 6. Configure Rate Limiting (1 hour)
- Supabase Dashboard → Settings → API → Rate Limiting
- Set reasonable limits (60 req/min per user)

#### 7. Document PII & Secrets (2 hours)
- List all PII collected
- Verify all secrets in Supabase Edge Function secrets (not code)
- Document locations

### Defer (Can Do Later)

- Certificate pinning (nice-to-have)
- Advanced monitoring/alerting (can add later)
- Privacy policy (needed before launch, not urgent now)
- GDPR automation (can be manual initially)
- Automated security scanning (can add to CI/CD later)

---

## Implementation Checklist (Essential Only)

### Day 1: Quick Wins
- [ ] Verify RLS policies exist and work
- [ ] Add missing RLS policies if needed
- [ ] Add authorization checks to 3-5 critical Edge Functions
- [ ] Migrate iOS credentials to Keychain

### Day 2: Critical Items
- [ ] Audit and fix RPC function security
- [ ] Configure rate limiting
- [ ] Document PII and secrets inventory

### Day 3: Testing & Documentation
- [ ] Test all security changes in staging
- [ ] Deploy to production
- [ ] Document what was done

**Total**: 2-3 days for essential security

---

## Related Documentation

- `DEPLOYMENT_WORKFLOW.md` - Deployment security (secrets)
- `ARCHITECTURE.md` - System architecture
- `docs/KNOWN_ISSUES.md` - Known security issues

---

**Status**: Streamlined to essential items. Start with Quick Wins when ready.

