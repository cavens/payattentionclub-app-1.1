# Testing Mode Consolidation Analysis
**Date**: 2026-01-17  
**Question**: Why is testing mode stored in two places? Can it be consolidated?

---

## Current State: Two Locations

### 1. Edge Function Secrets (`TESTING_MODE` environment variable)
- **Location**: Supabase Dashboard → Edge Functions → Settings → Secrets
- **Accessed by**: Edge Functions (TypeScript/Deno runtime)
- **Access method**: `Deno.env.get("TESTING_MODE")`
- **Used in**:
  - `_shared/timing.ts` (module-level constant)
  - `super-service/index.ts`
  - `preview-service/index.ts`
  - `bright-service/index.ts`
  - `testing-command-runner/index.ts` (also checks database as fallback)

### 2. Database `app_config` Table (`testing_mode`)
- **Location**: `public.app_config` table in PostgreSQL
- **Accessed by**: Database RPC functions, Cron jobs (PostgreSQL)
- **Access method**: SQL query `SELECT value FROM app_config WHERE key = 'testing_mode'`
- **Used in**:
  - `process_reconciliation_queue.sql` (cron job)
  - `testing-command-runner/index.ts` (fallback check)

---

## Why Two Locations Exist

### Technical Constraint: Runtime Separation

**Edge Functions (Deno Runtime)**:
- ✅ Can access environment variables via `Deno.env.get()`
- ✅ Can query database via Supabase client
- ❌ Cannot directly access PostgreSQL environment variables

**Database RPC Functions & Cron Jobs (PostgreSQL Runtime)**:
- ✅ Can query database tables (including `app_config`)
- ❌ **CANNOT access Edge Function environment variables**
- ❌ PostgreSQL has no access to Deno runtime environment

**Key Insight**: These are **two separate runtimes** that cannot share environment variables directly.

---

## Can We Consolidate?

### Option 1: Use Only `app_config` Table (Database)

**Implementation**:
- Remove `TESTING_MODE` from Edge Function secrets
- All Edge Functions query `app_config` table on startup or per-request

**Pros**:
- ✅ Single source of truth
- ✅ Accessible by both Edge Functions and database
- ✅ No inconsistency possible

**Cons**:
- ❌ **Performance hit**: Every Edge Function call needs database query
- ❌ **Module-level constants break**: `_shared/timing.ts` exports `TESTING_MODE` as constant (evaluated at module load)
- ❌ **Complexity**: Need to make async database calls in synchronous contexts
- ❌ **Caching needed**: Would need to cache the value to avoid repeated queries

**Feasibility**: ⚠️ **Difficult** - Would require significant refactoring

---

### Option 2: Use Only Environment Variable (Edge Functions)

**Implementation**:
- Remove `app_config.testing_mode`
- Database functions... **CANNOT ACCESS IT** ❌

**Pros**:
- ✅ Fast access in Edge Functions
- ✅ No database query needed

**Cons**:
- ❌ **Impossible for database functions**: PostgreSQL cannot access Deno environment variables
- ❌ Cron jobs cannot check testing mode
- ❌ RPC functions cannot check testing mode

**Feasibility**: ❌ **Not Possible** - Database functions need database config

---

### Option 3: Keep Both, Make Database Primary (Hybrid)

**Implementation**:
- Make `app_config` table the **primary source of truth**
- Edge Functions check database first, fallback to environment variable
- Database functions use `app_config` only
- Environment variable becomes optional/legacy

**Pros**:
- ✅ Single source of truth (database)
- ✅ Works for both runtimes
- ✅ Backward compatible (env var as fallback)
- ✅ Can remove env var requirement eventually

**Cons**:
- ⚠️ Still two places (but one is primary, one is fallback)
- ⚠️ Performance: Edge Functions need database query (but can cache)

**Feasibility**: ✅ **Feasible** - Similar to what `testing-command-runner` already does

---

### Option 4: Keep Both, Sync Automatically (Current + Sync)

**Implementation**:
- Keep both locations
- Add sync mechanism: When `app_config` changes, update Edge Function secrets (or vice versa)
- Or: Edge Functions always check both, database always checks `app_config`

**Pros**:
- ✅ Fast access in Edge Functions (env var)
- ✅ Works for database functions (app_config)
- ✅ No performance hit

**Cons**:
- ❌ **Complexity**: Need sync mechanism
- ❌ **Still two places**: Risk of inconsistency
- ❌ **Manual sync required**: Or automated sync (more complexity)

**Feasibility**: ⚠️ **Complex** - Requires sync infrastructure

---

## Recommended Approach: Option 3 (Database Primary)

### Why This Is Best

1. **Single Source of Truth**: Database `app_config` table becomes the authoritative source
2. **Works for All Runtimes**: Both Edge Functions and database can access it
3. **Backward Compatible**: Edge Functions can still check environment variable as fallback
4. **Already Partially Implemented**: `testing-command-runner` already does this!

### Implementation Plan

#### Step 1: Update `_shared/timing.ts`

**Current**:
```typescript
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
```

**New** (async function):
```typescript
let cachedTestingMode: boolean | null = null;
let cacheTimestamp: number = 0;
const CACHE_TTL_MS = 60000; // 1 minute cache

export async function getTestingMode(supabase?: SupabaseClient): Promise<boolean> {
  // Check cache first
  const now = Date.now();
  if (cachedTestingMode !== null && (now - cacheTimestamp) < CACHE_TTL_MS) {
    return cachedTestingMode;
  }

  // Check database first (primary source)
  if (supabase) {
    try {
      const { data: config } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'testing_mode')
        .single();
      
      if (config && config.value === 'true') {
        cachedTestingMode = true;
        cacheTimestamp = now;
        return true;
      }
    } catch (error) {
      // Fall through to env var check
    }
  }

  // Fallback to environment variable
  const envMode = Deno.env.get("TESTING_MODE") === "true";
  cachedTestingMode = envMode;
  cacheTimestamp = now;
  return envMode;
}

// For backward compatibility, keep constant (but it's now just env var)
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
```

**Problem**: This breaks module-level constants. Functions that use `TESTING_MODE` at module level won't work.

**Better Approach**: Update each Edge Function to check database on request, not at module level.

---

#### Step 2: Update Edge Functions

**Pattern for each function**:
```typescript
serve(async (req) => {
  // Check testing mode (database first, env var fallback)
  const supabase = createClient(supabaseUrl, supabaseSecretKey);
  const isTestingMode = await getTestingMode(supabase);
  
  // Use isTestingMode instead of TESTING_MODE constant
  if (isTestingMode) {
    // Testing mode logic
  }
});
```

**Functions to update**:
- `super-service/index.ts`
- `preview-service/index.ts`
- `bright-service/index.ts`
- `testing-command-runner/index.ts` (already does this!)

---

#### Step 3: Keep Database Functions As-Is

**No changes needed** - They already use `app_config`:
- `process_reconciliation_queue.sql` ✅

---

## Alternative: Simpler Approach (Recommended)

### Keep Current System, But Make Database Primary

**Strategy**:
1. **Document**: `app_config` table is the primary source of truth
2. **Update Edge Functions**: Check database first, env var as fallback (like `testing-command-runner`)
3. **Keep env var**: For backward compatibility and performance (cached)
4. **Remove env var requirement**: Eventually, once all functions check database

**Benefits**:
- ✅ Minimal code changes
- ✅ Works immediately
- ✅ Backward compatible
- ✅ Can migrate gradually

**Implementation**:
- Update `super-service`, `preview-service`, `bright-service` to check database like `testing-command-runner` does
- Keep `_shared/timing.ts` constant for now (used at module level)
- Document that `app_config` is primary, env var is fallback

---

## Summary

### Can We Consolidate to One Location?

**Short Answer**: **Not easily, due to runtime separation.**

**Long Answer**:
- **Edge Functions** (Deno) can access env vars but not share them with PostgreSQL
- **Database functions** (PostgreSQL) can access `app_config` but not Deno env vars
- **Best approach**: Make `app_config` primary, env var as fallback
- **Current state**: Already partially implemented in `testing-command-runner`

### Recommendation

**Keep both, but make database primary**:
1. ✅ `app_config` table = **Primary source of truth**
2. ✅ Edge Function env var = **Fallback/performance optimization**
3. ✅ Update all Edge Functions to check database first (like `testing-command-runner`)
4. ✅ Document that `app_config` is authoritative

**This gives us**:
- Single source of truth (database)
- Fast access in Edge Functions (cached env var)
- Works for all runtimes
- Minimal code changes

---

## Migration Path

1. **Phase 1**: Update all Edge Functions to check database first (like `testing-command-runner`)
2. **Phase 2**: Document that `app_config` is primary
3. **Phase 3**: Eventually remove env var requirement (optional)

**Estimated Effort**: Low - Just update 3-4 Edge Functions to check database


