# Security Analysis: Making `bright-service` Public

**Date**: 2026-01-17  
**Function**: `supabase/functions/bright-service/index.ts`  
**Question**: Are there security risks with making this function public?

---

## Executive Summary

**⚠️ HIGH RISK**: Making `bright-service` public in **production mode** would be a **critical security vulnerability**. However, in **testing mode only**, with proper safeguards, it can be acceptable.

---

## What This Function Does

The `bright-service` Edge Function processes weekly settlements:

1. **Reads commitment data** from the database
2. **Calculates penalties** based on usage
3. **Creates Stripe PaymentIntents** to charge users' payment methods
4. **Updates database records** with settlement status
5. **Handles financial transactions** (actual charges and worst-case charges)

**This is a financial transaction function** - it directly charges users' credit cards.

---

## Current Security Measures

### 1. **Testing Mode Protection** (Lines 529-537)
```typescript
if (isTestingMode) {
  const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
  if (!isManualTrigger) {
    return new Response(JSON.stringify({ 
      message: "Settlement skipped - testing mode active. Use x-manual-trigger: true header to run." 
    }), { status: 200 });
  }
}
```

**Protection**: Requires `x-manual-trigger: true` header in testing mode.

**⚠️ Weakness**: This header is **not a security measure** - it's just a flag to distinguish manual triggers from cron jobs. Anyone can add this header.

### 2. **Production Mode Comment** (Lines 540-543)
```typescript
} else {
  // In production mode, authentication is still required by Edge Function gateway
  // (This code path won't execute if gateway requires auth, but kept for clarity)
}
```

**Protection**: Comment suggests authentication is required, but **this is only true if the function is NOT public**.

### 3. **Business Logic Safeguards**
- Only processes commitments where grace period has expired (line 587)
- Only processes commitments that aren't already settled (line 580)
- Validates payment methods exist (line 601)
- Validates Stripe customer exists (line 596)
- Skips zero-amount charges (line 606)

**These are business logic checks, NOT security measures.**

---

## Security Risks if Made Public

### 🔴 **CRITICAL RISKS (Production Mode)**

1. **Unauthorized Financial Charges**
   - Anyone can trigger settlements at any time
   - Could charge users prematurely (before grace period expires)
   - Could cause duplicate charges if called multiple times
   - Could target specific weeks via `targetWeek` parameter

2. **Denial of Service (DoS)**
   - Attackers could spam the function
   - Each call processes all eligible commitments
   - Could cause:
     - Excessive Stripe API calls (rate limiting, costs)
     - Database load
     - Unnecessary charges to users

3. **Timing Attacks**
   - Could trigger settlements at wrong times
   - Could bypass grace periods by manipulating `targetWeek` parameter
   - Could cause financial discrepancies

4. **Information Disclosure**
   - Function returns detailed summary of:
     - Number of commitments
     - User IDs in failure messages
     - Settlement status
   - Could leak business intelligence

### 🟡 **MODERATE RISKS (Testing Mode)**

1. **Testing Mode Bypass**
   - If `app_config.testing_mode` is accidentally set to `true` in production
   - Function becomes public and can charge real users
   - The `x-manual-trigger` header is not a security measure

2. **Configuration Error**
   - If testing mode is enabled in production database
   - Function becomes public even if environment variable says otherwise

---

## Recommended Security Approach

### ✅ **Option 1: Keep Function Private (Recommended)**

**For Production**:
- Keep function **private** (requires authentication)
- Use Supabase service role key or JWT token to invoke
- Only allow cron jobs and authorized scripts to call it

**For Testing**:
- Use Supabase CLI with service role key:
  ```bash
  supabase functions invoke bright-service \
    --method POST \
    --body '{"targetWeek": null}' \
    --headers '{"x-manual-trigger": "true"}'
  ```

**Pros**:
- ✅ Maximum security
- ✅ No risk of unauthorized access
- ✅ Works in both testing and production

**Cons**:
- ⚠️ Requires service role key for testing
- ⚠️ Slightly more complex for manual triggers

---

### ✅ **Option 2: Conditional Public Access (Testing Mode Only)**

**Implementation**:
1. Make function public in Supabase Dashboard
2. Add **additional security check** in function code:

```typescript
// Add at the start of handler, before any processing
if (!isTestingMode) {
  // In production, require authentication
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ error: "Authentication required in production mode" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }
  // Validate JWT token here if needed
}
```

**Pros**:
- ✅ Allows public access in testing mode
- ✅ Blocks unauthorized access in production

**Cons**:
- ⚠️ Relies on `isTestingMode` check (could be bypassed if config is wrong)
- ⚠️ Still vulnerable if testing mode is accidentally enabled in production

---

### ✅ **Option 3: Secret Header Authentication**

**Implementation**:
Add a secret header that must match an environment variable:

```typescript
const SETTLEMENT_SECRET = Deno.env.get("SETTLEMENT_SECRET");
if (!SETTLEMENT_SECRET) {
  return new Response(
    JSON.stringify({ error: "Settlement secret not configured" }),
    { status: 500 }
  );
}

const providedSecret = req.headers.get("x-settlement-secret");
if (providedSecret !== SETTLEMENT_SECRET) {
  return new Response(
    JSON.stringify({ error: "Invalid settlement secret" }),
    { status: 401 }
  );
}
```

**Pros**:
- ✅ Works even if function is public
- ✅ Can be used in both testing and production
- ✅ Simple to implement

**Cons**:
- ⚠️ Secret must be kept secure
- ⚠️ If secret leaks, function is compromised

---

## Current Issue: 401 Unauthorized

The current 401 error occurs because:
1. Function is **not public** in Supabase Dashboard
2. Edge Function gateway requires authentication
3. Service role key cannot be used directly as JWT

**Solution**: Use Supabase CLI or add proper authentication to test scripts.

---

## Recommendation

**For Testing**:
1. **Keep function private**
2. Use Supabase CLI with service role key for manual triggers
3. Or add secret header authentication (Option 3)

**For Production**:
1. **Never make function public**
2. Always require authentication
3. Only allow cron jobs and authorized services to invoke

**Best Practice**: Use a combination of:
- Function remains private (Supabase Dashboard setting)
- Service role key for authorized scripts
- Cron jobs for automated execution

---

## Code Changes Needed (If Making Public)

If you decide to make the function public for testing, add this security check at the start of the handler:

```typescript
// Add after line 473 (after method check)
// Security: Require authentication in production mode
if (!isTestingMode) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ 
        error: "Authentication required",
        message: "This function requires authentication in production mode"
      }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }
  // Optionally validate JWT token here
}
```

---

## Conclusion

**Making `bright-service` public is HIGH RISK** because:
1. It processes financial transactions
2. It charges users' credit cards
3. It has no built-in authentication when public
4. The `x-manual-trigger` header is not a security measure

**Recommended**: Keep the function private and use service role key for testing.


