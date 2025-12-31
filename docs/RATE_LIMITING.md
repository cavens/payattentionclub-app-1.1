# Rate Limiting Configuration

**Status**: 📋 Configuration Guide  
**Last Updated**: 2025-12-31

---

## Overview

Rate limiting protects the API from abuse, DDoS attacks, and cost overruns. This document outlines the rate limiting strategy for PayAttentionClub.

---

## Supabase Built-in Rate Limiting

Supabase provides built-in rate limiting for authentication endpoints. These are configured in `supabase/config.toml`:

### Current Configuration

```toml
[auth.rate_limit]
email_sent = 2                    # Emails per hour
sms_sent = 30                     # SMS messages per hour
anonymous_users = 30              # Anonymous sign-ins per hour per IP
token_refresh = 150               # Token refreshes per 5 minutes per IP
sign_in_sign_ups = 30            # Sign up/sign in requests per 5 minutes per IP
token_verifications = 30          # OTP/Magic link verifications per 5 minutes per IP
web3 = 30                         # Web3 logins per 5 minutes per IP
```

### What Supabase Provides

1. **Authentication Endpoints**: ✅ Built-in rate limiting
   - Sign up/sign in: 30 requests per 5 minutes per IP
   - Token refresh: 150 requests per 5 minutes per IP
   - Email OTP: 30 verifications per 5 minutes per IP

2. **RPC Functions**: ⚠️ Limited built-in protection
   - Supabase applies some rate limiting, but it's not easily configurable
   - Recommended: Implement custom rate limiting in Edge Functions

3. **Edge Functions**: ⚠️ No built-in rate limiting
   - Must implement custom rate limiting
   - Can use Supabase's rate limiting headers or custom logic

4. **REST API (PostgREST)**: ⚠️ Limited configuration
   - Supabase applies some default limits
   - Not easily configurable per endpoint

---

## Recommended Rate Limits

Based on the security plan, here are the recommended limits:

### Per-User Limits (Authenticated)

| Endpoint Type | Limit | Rationale |
|--------------|-------|-----------|
| **Authentication** | 5 requests/minute | Prevent brute force attacks |
| **RPC Calls** | 60 requests/minute | Allow normal app usage (1 req/sec) |
| **Edge Functions** | 30 requests/minute | Prevent abuse of compute resources |
| **Payment Endpoints** | 10 requests/minute | Prevent payment abuse/fraud |

### Per-IP Limits (Unauthenticated)

| Endpoint Type | Limit | Rationale |
|--------------|-------|-----------|
| **General API** | 100 requests/minute | Allow reasonable public access |
| **Authentication** | 10 requests/minute | Prevent brute force on sign-in |

---

## Implementation Strategy

### 1. Authentication Endpoints ✅

**Status**: Already configured via `config.toml`

**Current Limits**:
- Sign up/sign in: 30 requests per 5 minutes per IP
- Token refresh: 150 requests per 5 minutes per IP

**Recommendation**: These limits are reasonable and already in place.

---

### 2. RPC Functions ⚠️

**Status**: Limited built-in protection

**Options**:
1. **Use Edge Functions as Wrapper** (Recommended)
   - Wrap RPC calls in Edge Functions
   - Apply rate limiting in Edge Function
   - Edge Function calls RPC internally

2. **Custom Rate Limiting in RPC Functions**
   - Use PostgreSQL rate limiting extensions
   - Store rate limit state in database
   - More complex, not recommended

**Recommendation**: For critical RPC functions, wrap them in Edge Functions with rate limiting.

---

### 3. Edge Functions ⚠️

**Status**: No built-in rate limiting - **Needs Implementation**

**Implementation Options**:

#### Option A: Custom Rate Limiting Helper

Create a rate limiting utility for Edge Functions:

```typescript
// supabase/functions/_shared/rateLimit.ts

interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
  keyPrefix: string;
}

export async function checkRateLimit(
  req: Request,
  config: RateLimitConfig
): Promise<{ allowed: boolean; remaining: number; resetAt: number }> {
  // Use Supabase's built-in rate limiting or custom implementation
  // Store rate limit state in database or cache
  // Return rate limit status
}
```

#### Option B: Use Supabase Rate Limiting Headers

Supabase may provide rate limit headers. Check response headers:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

**Recommendation**: Implement custom rate limiting for critical Edge Functions (payment, commitment creation).

---

### 4. Payment Endpoints 🔴

**Status**: **Critical - Needs Implementation**

**Priority**: HIGH - Payment endpoints are high-value targets

**Implementation**:
1. Add rate limiting to `billing-status` Edge Function
2. Add rate limiting to `rapid-service` Edge Function
3. Limit: 10 requests/minute per user

**Example**:
```typescript
// In billing-status/index.ts
const rateLimit = await checkRateLimit(req, {
  maxRequests: 10,
  windowMs: 60 * 1000, // 1 minute
  keyPrefix: 'billing-status'
});

if (!rateLimit.allowed) {
  return new Response(
    JSON.stringify({ error: 'Rate limit exceeded' }),
    {
      status: 429,
      headers: {
        'X-RateLimit-Limit': rateLimit.maxRequests.toString(),
        'X-RateLimit-Remaining': rateLimit.remaining.toString(),
        'X-RateLimit-Reset': rateLimit.resetAt.toString(),
      }
    }
  );
}
```

---

## Configuration Steps

### Step 1: Review Current Settings (5 min)

1. Go to Supabase Dashboard: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl
2. Navigate to: **Settings** → **API** → **Rate Limiting** (if available)
3. Review current settings
4. Document what's configurable vs. what's fixed

### Step 2: Verify Auth Rate Limits (5 min)

1. Check `supabase/config.toml` for `[auth.rate_limit]` settings
2. Verify these are appropriate for production
3. Update if needed (requires redeploy)

### Step 3: Implement Edge Function Rate Limiting (30 min)

1. Create rate limiting helper: `supabase/functions/_shared/rateLimit.ts`
2. Add rate limiting to critical Edge Functions:
   - `billing-status` (10 req/min)
   - `rapid-service` (10 req/min)
   - `super-service` (30 req/min)
3. Test rate limiting

### Step 4: Document Limits (5 min)

1. Update this document with actual limits configured
2. Add rate limit headers to responses
3. Document how to test rate limiting

---

## Testing Rate Limiting

### Test Script

```typescript
// supabase/tests/test_rate_limiting.ts

Deno.test("Rate Limiting - Billing Status", async () => {
  // Make 11 requests rapidly
  // 11th request should return 429
});
```

### Manual Testing

1. Use `curl` or Postman to hit endpoint repeatedly
2. Check for `429 Too Many Requests` response
3. Verify rate limit headers in response

---

## Monitoring

### What to Monitor

1. **Rate Limit Violations**: Track 429 responses
2. **High Request Volumes**: Alert on unusual spikes
3. **Per-User Request Patterns**: Detect abuse

### Supabase Dashboard

- Go to **Logs** → **API Logs**
- Filter for 429 status codes
- Review rate limit violations

---

## Next Steps

- [ ] Review Supabase Dashboard for rate limiting settings
- [ ] Verify auth rate limits in `config.toml` are appropriate
- [ ] Implement custom rate limiting for Edge Functions (if needed)
- [ ] Add rate limiting to payment endpoints
- [ ] Test rate limiting
- [ ] Document actual limits configured
- [ ] Set up monitoring/alerts for rate limit violations

---

## References

- [Supabase Rate Limiting Docs](https://supabase.com/docs/guides/platform/rate-limits)
- [Supabase Auth Rate Limits](https://supabase.com/docs/guides/auth/rate-limits)
- [Edge Functions Best Practices](https://supabase.com/docs/guides/functions/best-practices)

