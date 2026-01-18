# Why We Also Need Edge Function Secrets (Not Just `app_config`)

**Date**: 2026-01-18  
**Purpose**: Explain why Edge Functions use environment variables even though they can query `app_config`

---

## The Question

**If Edge Functions CAN query `app_config` from the database, why do we also need Edge Function secrets? Why not use only `app_config`?**

**Short Answer**: Performance, module-level code, and security best practices.

---

## Why Not Only `app_config`?

### 🔴 **Reason 1: Performance - Database Query Adds Latency**

**Every Edge Function call would need a database query**:

```typescript
// If we only used app_config:
Deno.serve(async (req) => {
  // ❌ Every request needs a database query
  const { data } = await supabase
    .from('app_config')
    .select('value')
    .eq('key', 'testing_mode')
    .single();
  
  const isTestingMode = data?.value === 'true';
  // ... rest of function
});
```

**Performance Impact**:
- Database query: **~10-50ms** per request
- Environment variable: **~0.001ms** (instant, in-memory)
- **Difference**: 10,000-50,000x slower

**Real-World Impact**:
- Edge Function gets 100 requests/second
- Each request adds 20ms database query
- **Total added latency**: 2 seconds per second of requests
- **Result**: Function becomes slow and expensive

**With environment variables**:
```typescript
// ✅ Fast - no database query needed
const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
// Instant access, no network call
```

---

### 🔴 **Reason 2: Module-Level Constants**

**Some code needs values at module load time** (before any requests):

**File**: `_shared/timing.ts`
```typescript
// This is evaluated when the module loads (not per-request)
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";

// These constants are calculated at module load
export const WEEK_DURATION_MS = TESTING_MODE ? 180000 : 604800000;
export const GRACE_PERIOD_MS = TESTING_MODE ? 60000 : 86400000;
```

**Problem with `app_config` only**:
```typescript
// ❌ This doesn't work - can't use async in module-level code
export const TESTING_MODE = await getTestingModeFromDatabase(); // ERROR: Top-level await not allowed

// ❌ This also doesn't work - module loads before database connection exists
export const TESTING_MODE = getTestingModeFromDatabase(); // ERROR: Can't call async function synchronously
```

**Why it matters**:
- Module-level constants are used throughout the codebase
- They're evaluated once when the Edge Function starts
- They can't wait for a database query
- **Result**: Would require major refactoring of all timing code

---

### 🟡 **Reason 3: Cold Start Performance**

**Edge Functions have "cold starts"** - when a function hasn't been used recently:

**Cold Start Sequence**:
1. Function container starts (100-500ms)
2. Code loads and executes
3. **If using `app_config`**: Database connection + query (20-50ms)
4. Function ready to handle requests

**With environment variables**:
- Values are already in memory
- No database connection needed
- **Cold start is faster**

**Impact**:
- First request after idle period is slower
- User experiences delay
- More noticeable in serverless environments

---

### 🟡 **Reason 4: Secrets Security Best Practice**

**Some secrets should NOT be in the database**:

**Security Principle**: Secrets should be stored in the most secure location possible.

**Edge Function Secrets** (Supabase Dashboard):
- ✅ Encrypted at rest
- ✅ Encrypted in transit
- ✅ Not queryable via SQL
- ✅ Not in database backups
- ✅ Access controlled by Supabase platform

**`app_config` Table**:
- ✅ Encrypted at rest (database encryption)
- ✅ Encrypted in transit (database connections)
- ⚠️ Queryable via SQL (anyone with database access can read)
- ⚠️ Included in database backups
- ⚠️ Access controlled by database permissions

**Example: Stripe Secret Keys**

**If stored in `app_config`**:
```sql
-- Anyone with database read access can see:
SELECT * FROM app_config WHERE key = 'stripe_secret_key';
-- ❌ Secret key exposed in database
```

**If stored in Edge Function secrets**:
- ✅ Only Edge Function code can access it
- ✅ Not visible in database queries
- ✅ Better security isolation

**Best Practice**:
- **Sensitive secrets** (API keys, tokens) → Edge Function secrets
- **Configuration flags** (testing_mode, feature flags) → `app_config` table

---

### 🟡 **Reason 5: Complexity - Async in Synchronous Contexts**

**Many functions need config values synchronously**:

**Example**: `_shared/timing.ts`
```typescript
// This function is called synchronously
export function getNextDeadline(now?: Date): Date {
  // ❌ Can't await database query here - function is synchronous
  const isTestingMode = await getTestingModeFromDatabase(); // ERROR
  
  if (TESTING_MODE) { // ✅ Works with constant
    return new Date(now.getTime() + 180000);
  }
  // ...
}
```

**If we only used `app_config`**:
- Every function that needs config would need to be async
- Would require refactoring hundreds of function calls
- **Result**: Massive code changes, potential bugs

---

### 🟡 **Reason 6: Database Dependency**

**If database is unavailable, Edge Functions still need to work**:

**Scenario**: Database maintenance or outage

**With environment variables**:
- ✅ Edge Functions can still read config from env vars
- ✅ Functions continue to work (with cached config)
- ✅ Graceful degradation

**With only `app_config`**:
- ❌ Edge Functions can't read config if database is down
- ❌ Functions fail completely
- ❌ No fallback mechanism

**Real-World Example**:
- Database maintenance window: 2 hours
- Edge Functions still need to handle requests
- Environment variables provide fallback config

---

## The Hybrid Approach (Current Best Practice)

### Why Both Exist

**`app_config` Table**:
- ✅ Primary source of truth
- ✅ Accessible by database functions (required)
- ✅ Accessible by Edge Functions (with database query)
- ✅ Runtime changes without redeployment

**Edge Function Secrets**:
- ✅ Fast access (no database query)
- ✅ Module-level constants work
- ✅ Better security for sensitive secrets
- ✅ Works even if database is unavailable
- ✅ Performance optimization

### Current Pattern

**Edge Functions should**:
1. Check `app_config` first (primary source of truth)
2. Fallback to environment variable (performance/backup)
3. Cache the value to avoid repeated queries

**Example** (from `testing-command-runner`):
```typescript
// Check database first (primary)
const { data: config } = await supabase
  .from('app_config')
  .select('value')
  .eq('key', 'testing_mode')
  .single();

const isTestingMode = config?.value === 'true' 
  || Deno.env.get("TESTING_MODE") === "true"; // Fallback
```

---

## Could We Use Only `app_config`?

### Technically: Yes, but with significant tradeoffs

**What would be required**:

1. **Refactor all module-level constants**:
   - Make all timing functions async
   - Update all call sites to await
   - **Effort**: High (hundreds of changes)

2. **Accept performance hit**:
   - Every Edge Function call adds 20-50ms database query
   - **Impact**: Slower response times, higher costs

3. **Add caching layer**:
   - Cache `app_config` values in memory
   - Invalidate cache when config changes
   - **Complexity**: Medium (cache management)

4. **Handle database unavailability**:
   - Fallback mechanism when database is down
   - **Complexity**: Medium (error handling)

5. **Security considerations**:
   - Store sensitive secrets in database (less secure)
   - Or keep secrets in env vars anyway (defeats the purpose)

### Is It Worth It?

**Pros of only `app_config`**:
- ✅ Single source of truth
- ✅ No sync issues
- ✅ Simpler mental model

**Cons of only `app_config`**:
- ❌ Performance degradation (20-50ms per request)
- ❌ Major refactoring required
- ❌ Security concerns for secrets
- ❌ Complexity (caching, error handling)
- ❌ Cold start delays

**Verdict**: **Not worth it** - The performance and complexity costs outweigh the benefits.

---

## Recommended Approach

### Keep Both, But Make `app_config` Primary

**Strategy**:
1. **`app_config` table** = Primary source of truth (authoritative)
2. **Edge Function secrets** = Performance optimization + fallback
3. **Edge Functions check database first**, fallback to env var
4. **Sensitive secrets** stay in Edge Function secrets (security)

**Benefits**:
- ✅ Single source of truth (`app_config`)
- ✅ Fast access (env var as cache)
- ✅ Works for all runtimes
- ✅ Security best practices
- ✅ Minimal code changes

**Implementation**:
- Edge Functions: Check `app_config`, fallback to env var (like `testing-command-runner`)
- Database functions: Use `app_config` only (already done)
- Secrets: Keep in Edge Function secrets (security)

---

## Summary

### Why Not Only `app_config`?

1. **Performance**: Database queries add 20-50ms latency per request
2. **Module-level code**: Can't use async database calls in synchronous contexts
3. **Cold starts**: Environment variables are faster on function startup
4. **Security**: Sensitive secrets shouldn't be in queryable database tables
5. **Complexity**: Would require major refactoring of timing code
6. **Reliability**: Environment variables work even if database is unavailable

### Why Keep Both?

- **`app_config`**: Primary source of truth, accessible by all runtimes
- **Edge Function secrets**: Performance optimization, security for secrets, fallback

### The Best Approach

**Hybrid system**:
- `app_config` = Primary (authoritative)
- Edge Function secrets = Performance + security + fallback
- Edge Functions check database first, fallback to env var

This gives us the best of both worlds: single source of truth with fast performance.

