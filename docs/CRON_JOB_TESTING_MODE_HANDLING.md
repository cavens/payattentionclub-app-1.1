# Cron Job Handling in Testing Mode

**Purpose**: Explain how to automatically skip cron job calls when testing mode is enabled

---

## The Problem

When `TESTING_MODE=true`:
- Cron job still runs on schedule (e.g., every Monday at 12:00 ET)
- But we want settlement to run manually with controlled timing
- We need to distinguish between cron calls and manual triggers

---

## Solution: Check Testing Mode at Function Start

### Implementation

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

Add this check at the very beginning of the `Deno.serve` handler:

```typescript
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
    return new Response("Supabase credentials missing", { status: 500 });
  }

  // ✅ TESTING MODE CHECK - Skip if testing mode is enabled and not manually triggered
  const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
  if (TESTING_MODE) {
    // In testing mode, only allow manual triggers
    // Manual triggers include a special header to distinguish from cron
    const isManualTrigger = req.headers.get("x-manual-trigger") === "true" || 
                           req.headers.get("x-testing-trigger") === "true";
    
    if (!isManualTrigger) {
      // This is a cron call - skip it
      console.log("run-weekly-settlement: Skipped - testing mode active, cron call ignored");
      return new Response(
        JSON.stringify({ 
          message: "Settlement skipped - testing mode active. Use manual trigger with x-manual-trigger header." 
        }), 
        { 
          status: 200,
          headers: { "Content-Type": "application/json" }
        }
      );
    }
    console.log("run-weekly-settlement: Manual trigger in testing mode - proceeding");
  }

  // ... rest of existing code ...
  const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY);
  // ...
});
```

---

## How It Works

### Normal Mode (`TESTING_MODE=false` or not set)

1. **Cron calls function** → Function processes normally ✅
2. **Manual API calls** → Function processes normally ✅
3. **No special headers needed** → Everything works as usual

### Testing Mode (`TESTING_MODE=true`)

1. **Cron calls function** → Function checks for `x-manual-trigger` header → Not present → Returns early with message ✅
2. **Manual API calls** → Function checks for `x-manual-trigger` header → Present → Processes normally ✅

---

## Manual Trigger Methods

### Option 1: Supabase CLI with Header

```bash
# Using Supabase CLI (if it supports headers)
supabase functions invoke bright-service \
  --method POST \
  --header "x-manual-trigger: true" \
  --body '{"targetWeek": null}'
```

**Note**: Supabase CLI may not support custom headers. Use Option 2 or 3 instead.

---

### Option 2: Direct HTTP Request

```bash
# Get your Supabase project URL and anon key
SUPABASE_URL="https://your-project.supabase.co"
ANON_KEY="your-anon-key"

# Make request with manual trigger header
curl -X POST \
  "${SUPABASE_URL}/functions/v1/bright-service" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -H "x-manual-trigger: true" \
  -d '{"targetWeek": null}'
```

---

### Option 3: Test Script (Recommended)

**File**: `supabase/tests/manual_settlement_trigger.ts`

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function triggerSettlement(options?: { targetWeek?: string; now?: string }) {
  // Use Supabase function invoke with custom headers
  // Note: Supabase JS client may not support custom headers directly
  // So we use fetch directly
  
  const url = `${supabaseUrl}/functions/v1/bright-service`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${supabaseServiceKey}`,
      "x-manual-trigger": "true"  // ✅ Manual trigger header
    },
    body: JSON.stringify(options || {})
  });

  if (!response.ok) {
    const error = await response.text();
    console.error("❌ Settlement trigger failed:", error);
    throw new Error(`Settlement failed: ${error}`);
  }

  const data = await response.json();
  console.log("✅ Settlement triggered:", data);
  return data;
}

// Usage
const targetWeek = Deno.args[0] || null;
const now = Deno.args[1] || new Date().toISOString();

await triggerSettlement({ 
  targetWeek: targetWeek || undefined,
  now: now 
});
```

**Run it**:
```bash
deno run --allow-net --allow-env supabase/tests/manual_settlement_trigger.ts
```

---

## Alternative: Simpler Approach (No Header Check)

If you want to keep it even simpler, you can just check testing mode and always allow the function to run, but it will process nothing (no commitments ready for settlement in compressed timeline):

```typescript
Deno.serve(async (req) => {
  // ... existing checks ...

  const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
  if (TESTING_MODE) {
    console.log("run-weekly-settlement: Testing mode active - will process if commitments ready");
    // Continue normally - function will just find no commitments to settle
    // (because compressed timeline means commitments aren't ready yet)
  }

  // ... rest of code ...
});
```

**Why this works**:
- In testing mode, commitments have compressed deadlines (3 minutes from creation)
- Cron runs on fixed schedule (Monday 12:00 ET)
- When cron runs, no commitments will be ready for settlement (they're on compressed timeline)
- Function will process but find nothing to settle
- Manual triggers can pass `now` parameter to control timing

**Pros**: Simpler, no header checking needed  
**Cons**: Function still runs (wastes resources, but harmless)

---

## Recommended Approach

**Use the header check approach** (Option 1 above) because:
1. ✅ Explicitly prevents cron from running in testing mode
2. ✅ Clear logging when cron is skipped
3. ✅ No wasted function invocations
4. ✅ Makes testing mode behavior obvious

---

## Testing the Implementation

### Test 1: Cron Call (Should Skip)

1. Set `TESTING_MODE=true`
2. Wait for cron to run (or trigger manually without header)
3. Check logs: Should see "Skipped - testing mode active"
4. Check response: Should return 200 with skip message

### Test 2: Manual Trigger (Should Process)

1. Set `TESTING_MODE=true`
2. Trigger with `x-manual-trigger: true` header
3. Check logs: Should see "Manual trigger in testing mode - proceeding"
4. Check response: Should process normally

### Test 3: Normal Mode (Should Always Process)

1. Set `TESTING_MODE=false` (or unset)
2. Trigger with or without header
3. Check logs: Should process normally
4. Cron calls should work normally

---

## Summary

**Implementation**:
- Add `TESTING_MODE` check at start of settlement function
- Check for `x-manual-trigger` header
- Skip if testing mode + no header (cron call)
- Process if testing mode + header present (manual trigger)
- Always process if not testing mode

**Result**:
- ✅ Cron automatically skipped in testing mode
- ✅ Manual triggers work with header
- ✅ Normal mode unaffected
- ✅ No manual cron management needed

---

**End of Document**


