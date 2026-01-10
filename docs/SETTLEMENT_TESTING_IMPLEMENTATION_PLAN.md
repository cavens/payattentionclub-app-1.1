# Settlement Testing Implementation Plan

**Purpose**: Complete step-by-step plan for implementing compressed timeline testing mode  
**Goal**: Enable fast testing of all settlement cases (3 min week, 1 min grace period)  
**Duration**: Estimated 2-3 hours implementation time

---

## Overview

This plan implements:
1. ✅ Compressed timeline (3 min week, 1 min grace)
2. ✅ Automatic cron skip in testing mode
3. ✅ iOS app uses backend deadline (countdown shows compressed time)
4. ✅ Verification tools (SQL + TypeScript scripts)
5. ✅ Web interface for easy testing

---

## Phase 1: Backend - Testing Mode Infrastructure

### Step 1.1: Create Shared Timing Helper

**File**: `supabase/functions/_shared/timing.ts` (new)

**Purpose**: Centralized timing logic for compressed vs normal mode

**Implementation**:
```typescript
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
export const WEEK_DURATION_MS = TESTING_MODE ? 3 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
export const GRACE_PERIOD_MS = TESTING_MODE ? 1 * 60 * 1000 : 24 * 60 * 60 * 1000;

export function getNextDeadline(now: Date = new Date()): Date {
  if (TESTING_MODE) {
    return new Date(now.getTime() + WEEK_DURATION_MS);
  }
  // ... existing Monday calculation logic ...
}

export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  const grace = new Date(weekEndDate);
  grace.setDate(grace.getDate() + 1);
  return grace;
}
```

**Dependencies**: None  
**Testing**: Verify constants export correctly

---

### Step 1.2: Update Settlement Function - Compressed Timing

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

**Changes**:
1. Import timing helper
2. Update `resolveWeekTarget()` to use compressed grace period
3. Add cron skip logic at function start

**Implementation**:
```typescript
import { TESTING_MODE, getGraceDeadline } from "../_shared/timing.ts";

// At start of Deno.serve handler:
const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
if (TESTING_MODE) {
  const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
  if (!isManualTrigger) {
    return new Response(JSON.stringify({ 
      message: "Settlement skipped - testing mode active" 
    }), { status: 200 });
  }
}

// In resolveWeekTarget():
const graceDeadline = getGraceDeadline(monday);
```

**Dependencies**: Step 1.1  
**Testing**: Verify settlement uses compressed timing in testing mode

---

### Step 1.3: Update Commitment Creation - Compressed Deadline

**File**: `supabase/functions/super-service/index.ts`

**Changes**:
1. Import timing helper
2. Calculate compressed deadline when `TESTING_MODE=true`
3. Pass compressed deadline to RPC

**Implementation**:
```typescript
import { TESTING_MODE, getNextDeadline } from "../_shared/timing.ts";

// In commitment creation handler:
const deadlineDate = TESTING_MODE 
  ? getNextDeadline()  // 3 minutes from now
  : getNextMondayDeadline();  // Next Monday

const deadlineDateString = formatDate(deadlineDate);
```

**Dependencies**: Step 1.1  
**Testing**: Verify commitments created with compressed deadline in testing mode

---

### Step 1.4: Fix Grace Period Calculation Bug

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

**Changes**:
1. Fix `isGracePeriodExpired()` to use correct timezone (Tuesday 12:00 ET)
2. Use timing helper for compressed mode

**Implementation**:
```typescript
function isGracePeriodExpired(candidate: SettlementCandidate, reference: Date = new Date()): boolean {
  const explicit = candidate.commitment.week_grace_expires_at;
  if (explicit) return new Date(explicit).getTime() <= reference.getTime();

  if (TESTING_MODE) {
    // Compressed: grace period is 1 minute after deadline
    const weekEnd = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
    const graceExpires = new Date(weekEnd.getTime() + GRACE_PERIOD_MS);
    return graceExpires.getTime() <= reference.getTime();
  }

  // Normal mode: Tuesday 12:00 ET
  const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
  const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
  const tuesdayET = new Date(mondayET);
  tuesdayET.setDate(tuesdayET.getDate() + 1);
  tuesdayET.setHours(12, 0, 0, 0);
  return tuesdayET.getTime() <= reference.getTime();
}
```

**Dependencies**: Step 1.1  
**Testing**: Verify grace period expires at correct time (compressed and normal)

---

## Phase 2: iOS App - Use Backend Deadline

### Step 2.1: Update AuthorizationView to Use Backend Deadline

**File**: `payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/Views/AuthorizationView.swift`

**Changes**:
1. After commitment creation, parse `commitmentResponse.deadlineDate`
2. Store backend deadline instead of recalculating locally

**Implementation**:
```swift
// After commitment creation (around line 261):
let commitmentResponse = try await BackendClient.shared.createCommitment(...)

// Parse deadline from backend response
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd"
dateFormatter.timeZone = TimeZone(identifier: "America/New_York")

if let deadlineDate = dateFormatter.date(from: commitmentResponse.deadlineDate) {
    // Store backend deadline (not local calculation)
    UsageTracker.shared.storeCommitmentDeadline(deadlineDate)
    NSLog("AUTH AuthorizationView: ✅ Using backend deadline: \(deadlineDate)")
} else {
    // Fallback to local calculation if parsing fails
    let deadline = await MainActor.run { model.getNextMondayNoonEST() }
    UsageTracker.shared.storeCommitmentDeadline(deadline)
    NSLog("AUTH AuthorizationView: ⚠️ Fallback to local deadline calculation")
}
```

**Dependencies**: None  
**Testing**: Verify countdown shows backend deadline (compressed in testing mode)

---

## Phase 3: Verification Tools

### Step 3.1: Create Verification SQL Function

**File**: `supabase/remote_rpcs/rpc_verify_test_settlement.sql` (new)

**Purpose**: Single SQL function to get all test results

**Implementation**:
```sql
CREATE OR REPLACE FUNCTION public.rpc_verify_test_settlement(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_result json;
  v_commitment json;
  v_penalty json;
  v_payments json;
  v_usage_count integer;
BEGIN
  -- Get latest commitment
  SELECT row_to_json(c.*) INTO v_commitment
  FROM public.commitments c
  WHERE c.user_id = p_user_id
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- Get latest penalty record
  SELECT row_to_json(uwp.*) INTO v_penalty
  FROM public.user_week_penalties uwp
  WHERE uwp.user_id = p_user_id
  ORDER BY uwp.week_start_date DESC
  LIMIT 1;

  -- Get all payments
  SELECT json_agg(row_to_json(p.*)) INTO v_payments
  FROM public.payments p
  WHERE p.user_id = p_user_id
  ORDER BY p.created_at DESC;

  -- Count usage entries
  SELECT COUNT(*) INTO v_usage_count
  FROM public.daily_usage
  WHERE user_id = p_user_id;

  -- Build result
  v_result := json_build_object(
    'commitment', v_commitment,
    'penalty', v_penalty,
    'payments', COALESCE(v_payments, '[]'::json),
    'usage_count', v_usage_count,
    'verification_time', NOW()
  );

  RETURN v_result;
END;
$$;
```

**Dependencies**: None  
**Testing**: Test function with test user ID

---

### Step 3.2: Create Verification TypeScript Script

**File**: `supabase/tests/verify_test_results.ts` (new)

**Purpose**: Command-line script to verify test results

**Implementation**:
```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

async function verifyTestResults(userId: string) {
  const { data, error } = await supabase.rpc('rpc_verify_test_settlement', {
    p_user_id: userId
  });

  if (error) {
    console.error("❌ Verification failed:", error);
    return;
  }

  console.log("\n📊 TEST RESULTS VERIFICATION");
  console.log("============================\n");

  if (data.commitment) {
    console.log("✅ Commitment:", {
      id: data.commitment.id,
      deadline: data.commitment.week_end_date,
      grace_expires: data.commitment.week_grace_expires_at,
      max_charge: data.commitment.max_charge_cents,
      status: data.commitment.status
    });
  }

  if (data.penalty) {
    console.log("\n✅ Penalty Record:", {
      status: data.penalty.settlement_status,
      charged: data.penalty.charged_amount_cents,
      actual: data.penalty.actual_amount_cents,
      needs_reconciliation: data.penalty.needs_reconciliation,
      delta: data.penalty.reconciliation_delta_cents
    });
  }

  console.log(`\n✅ Payments: ${data.payments?.length || 0}`);
  data.payments?.forEach((p: any, i: number) => {
    console.log(`  ${i + 1}. ${p.type}: ${p.amount_cents} cents (${p.status})`);
  });

  console.log(`\n✅ Usage Entries: ${data.usage_count}`);
  console.log("\n============================\n");
}

const userId = Deno.args[0];
if (!userId) {
  console.error("Usage: deno run verify_test_results.ts <user-id>");
  Deno.exit(1);
}

await verifyTestResults(userId);
```

**Dependencies**: Step 3.1  
**Testing**: Run script with test user ID

---

### Step 3.3: Create Manual Settlement Trigger Script

**File**: `supabase/tests/manual_settlement_trigger.ts` (new)

**Purpose**: Command-line script to trigger settlement manually

**Implementation**:
```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function triggerSettlement(options?: { targetWeek?: string; now?: string }) {
  const url = `${supabaseUrl}/functions/v1/bright-service`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${supabaseServiceKey}`,
      "x-manual-trigger": "true"  // Required in testing mode
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

const targetWeek = Deno.args[0] || null;
const now = Deno.args[1] || new Date().toISOString();

await triggerSettlement({ 
  targetWeek: targetWeek || undefined,
  now: now 
});
```

**Dependencies**: Step 1.2  
**Testing**: Trigger settlement in testing mode

---

## Phase 4: Testing Command Runner Edge Function

### Step 4.1: Create Command Runner Edge Function

**File**: `supabase/functions/testing-command-runner/index.ts` (new)

**Purpose**: Server-side execution of all testing commands

**Implementation Structure**:
```typescript
// Check testing mode
const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
if (!TESTING_MODE) {
  return new Response("Testing mode not enabled", { status: 403 });
}

// Parse command from request
const { command, userId, params } = await req.json();

switch (command) {
  case "clear_data":
    // Execute clear test data logic
    break;
  case "trigger_settlement":
    // Call settlement function with manual trigger header
    break;
  case "trigger_reconciliation":
    // Call reconciliation function
    break;
  case "verify_results":
    // Call rpc_verify_test_settlement
    break;
  case "get_commitment":
    // Query latest commitment
    break;
  case "get_usage":
    // Query usage data
    break;
  case "get_penalty":
    // Query penalty record
    break;
  case "get_payments":
    // Query payments
    break;
  case "sql_query":
    // Execute safe SQL query (with validation)
    break;
  default:
    return new Response("Unknown command", { status: 400 });
}
```

**Commands to Implement**:
1. `clear_data` - Delete all test user data
2. `trigger_settlement` - Trigger settlement with manual header
3. `trigger_reconciliation` - Trigger reconciliation
4. `verify_results` - Get complete verification
5. `get_commitment` - Get latest commitment
6. `get_usage` - Get usage entries
7. `get_penalty` - Get penalty record
8. `get_payments` - Get payment records
9. `sql_query` - Execute safe SQL (read-only, user-scoped)

**Dependencies**: Steps 1.1, 1.2, 3.1  
**Testing**: Test each command individually

---

## Phase 5: Web Testing Interface

### Step 5.1: Create HTML Interface

**File**: `supabase/tests/testing-dashboard.html` (new)

**Structure**:
- HTML page with organized sections
- Input field for user ID
- Buttons for each command organized by test case
- Results display area
- Basic styling

**Sections**:
1. Header with user ID input
2. Pre-Test Setup section
3. Test Case 1 section
4. Test Case 2 section
5. Test Case 3A section
6. Test Case 3B section
7. Test Case 3C section
8. Post-Test Cleanup section
9. Results panel

**Dependencies**: Step 4.1  
**Testing**: Verify all buttons render correctly

---

### Step 5.2: Add JavaScript for Command Execution

**File**: `supabase/tests/testing-dashboard.js` (new, or inline in HTML)

**Functions**:
- `executeCommand(command, params)` - Calls command runner
- `displayResults(data)` - Shows results in panel
- `formatJSON(data)` - Pretty-prints JSON
- `copyToClipboard(text)` - Copies to clipboard
- `saveUserId()` - Saves user ID to localStorage
- `loadUserId()` - Loads user ID from localStorage

**Implementation**:
```javascript
const SUPABASE_URL = 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = 'your-anon-key';

async function executeCommand(command, params = {}) {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/testing-command-runner`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
    },
    body: JSON.stringify({ command, ...params })
  });

  const data = await response.json();
  displayResults(data);
  return data;
}

function displayResults(data) {
  const resultsPanel = document.getElementById('results');
  resultsPanel.textContent = JSON.stringify(data, null, 2);
  resultsPanel.style.display = 'block';
}
```

**Dependencies**: Step 5.1, Step 4.1  
**Testing**: Test each button click

---

### Step 5.3: Add Styling

**File**: `supabase/tests/testing-dashboard.css` (new, or inline in HTML)

**Styles**:
- Clean, organized layout
- Color-coded sections
- Button styling
- Results panel styling
- Responsive design

**Dependencies**: Step 5.1  
**Testing**: Verify visual appearance

---

### Step 5.4: Serve the Interface

**Option A: Local File** (Simplest)
- Open `testing-dashboard.html` directly in browser
- Uses CORS to call Supabase functions

**Option B: Edge Function Serves HTML**
- Add route to `testing-command-runner` to serve HTML
- Access via: `https://project.supabase.co/functions/v1/testing-command-runner/dashboard`

**Option C: Simple HTTP Server**
- `python -m http.server 8000` or `deno serve --port 8000`
- Access via: `http://localhost:8000/testing-dashboard.html`

**Dependencies**: Steps 5.1, 5.2, 5.3  
**Testing**: Verify interface loads and functions work

---

## Phase 6: Environment Setup

### Step 6.1: Set Testing Mode Environment Variable

**Location**: Supabase Dashboard → Project Settings → Edge Functions → Environment Variables

**Action**: Set `TESTING_MODE=true` in staging environment

**Dependencies**: None  
**Testing**: Verify environment variable is set

---

### Step 6.2: Deploy All Functions

**Commands**:
```bash
# Deploy updated functions
supabase functions deploy bright-service
supabase functions deploy super-service
supabase functions deploy testing-command-runner

# Deploy new RPC function
# (Apply migration for rpc_verify_test_settlement)
```

**Dependencies**: All previous steps  
**Testing**: Verify all functions deploy successfully

---

## Phase 7: Testing & Validation

### Step 7.1: Test Compressed Timeline

**Actions**:
1. Enable testing mode
2. Create commitment via iOS app
3. Verify deadline is ~3 minutes from now
4. Verify countdown shows ~3 minutes
5. Wait 1 minute, verify grace period expires
6. Trigger settlement manually
7. Verify settlement works correctly

**Dependencies**: All previous steps  
**Expected**: Compressed timeline works end-to-end

---

### Step 7.2: Test All Settlement Cases

**Actions**:
1. Run through Test Case 1 using web interface
2. Run through Test Case 2 using web interface
3. Run through Test Case 3A using web interface
4. Run through Test Case 3B using web interface
5. Run through Test Case 3C using web interface

**Dependencies**: Step 7.1  
**Expected**: All cases work correctly

---

### Step 7.3: Test Cron Skip

**Actions**:
1. Enable testing mode
2. Wait for cron to run (or simulate)
3. Verify settlement is skipped
4. Trigger manually with header
5. Verify settlement processes

**Dependencies**: Step 1.2  
**Expected**: Cron skips, manual triggers work

---

## Phase 8: Documentation

### Step 8.1: Update Testing Script Document

**File**: `docs/SETTLEMENT_TESTING_SCRIPT.md`

**Updates**:
- Add web interface instructions
- Update commands to reference web interface
- Add screenshots/examples

**Dependencies**: Phase 5 complete  
**Testing**: Verify documentation is accurate

---

### Step 8.2: Create Quick Start Guide

**File**: `docs/TESTING_QUICK_START.md` (new)

**Content**:
- How to enable testing mode
- How to access web interface
- Quick test workflow
- Troubleshooting

**Dependencies**: All phases complete  
**Testing**: Verify guide is clear and complete

---

## Implementation Order

### Week 1: Core Functionality
1. ✅ Phase 1: Backend Testing Mode (Steps 1.1-1.4)
2. ✅ Phase 2: iOS App Fix (Step 2.1)
3. ✅ Phase 6: Environment Setup (Step 6.1)

### Week 2: Tools & Interface
4. ✅ Phase 3: Verification Tools (Steps 3.1-3.3)
5. ✅ Phase 4: Command Runner (Step 4.1)
6. ✅ Phase 5: Web Interface (Steps 5.1-5.4)

### Week 3: Testing & Polish
7. ✅ Phase 6: Deploy (Step 6.2)
8. ✅ Phase 7: Testing (Steps 7.1-7.3)
9. ✅ Phase 8: Documentation (Steps 8.1-8.2)

---

## Dependencies Map

```
Step 1.1 (Timing Helper)
  ├─> Step 1.2 (Settlement Function)
  ├─> Step 1.3 (Commitment Creation)
  └─> Step 1.4 (Grace Period Fix)

Step 1.2
  └─> Step 3.3 (Manual Trigger Script)

Step 3.1 (Verification SQL)
  └─> Step 3.2 (Verification Script)

Step 1.2 + Step 3.1
  └─> Step 4.1 (Command Runner)

Step 4.1
  └─> Step 5.1 (HTML Interface)
      └─> Step 5.2 (JavaScript)
          └─> Step 5.3 (Styling)
              └─> Step 5.4 (Serve Interface)

All Steps
  └─> Phase 7 (Testing)
      └─> Phase 8 (Documentation)
```

---

## Success Criteria

### Functional Requirements
- ✅ Compressed timeline works (3 min week, 1 min grace)
- ✅ iOS countdown shows compressed time
- ✅ Cron automatically skips in testing mode
- ✅ Manual triggers work with header
- ✅ All settlement cases testable
- ✅ Verification tools work
- ✅ Web interface functional

### Non-Functional Requirements
- ✅ Testing mode only works in staging
- ✅ Security: Requires authentication/secret
- ✅ Performance: Commands execute quickly
- ✅ Usability: Web interface is intuitive
- ✅ Documentation: Complete and clear

---

## Risk Mitigation

### Risk 1: Testing Mode Leaks to Production
**Mitigation**: 
- Check `TESTING_MODE` in all functions
- Never set in production environment
- Add warnings in code

### Risk 2: Web Interface Security
**Mitigation**:
- Require authentication
- Validate all inputs
- Rate limiting
- Only enable in staging

### Risk 3: SQL Injection in Command Runner
**Mitigation**:
- Only allow read-only queries
- Validate SQL syntax
- Scope queries to user_id
- Whitelist allowed operations

### Risk 4: iOS App Deadline Parsing Fails
**Mitigation**:
- Fallback to local calculation
- Log parsing errors
- Test with various date formats

---

## Estimated Time

- **Phase 1**: 45 minutes (Backend infrastructure)
- **Phase 2**: 15 minutes (iOS app fix)
- **Phase 3**: 30 minutes (Verification tools)
- **Phase 4**: 60 minutes (Command runner)
- **Phase 5**: 90 minutes (Web interface)
- **Phase 6**: 15 minutes (Environment setup)
- **Phase 7**: 60 minutes (Testing)
- **Phase 8**: 30 minutes (Documentation)

**Total**: ~5.5 hours

---

## Next Steps

**CURRENT STATUS (Active Work):**
- ✅ **Auto-Settlement Infrastructure Deployed** - `auto-settlement-checker` Edge Function and `pg_cron` job are deployed and active
- 🔧 **Testing Automatic Settlement** - Investigating why automatic settlement didn't trigger after grace period expired

**Test Results Analysis (2026-01-10):**
- ✅ Commitment created successfully at `22:32:16`
- ✅ Usage synced within grace period (22 cents penalty calculated)
- ❌ **Issue**: Settlement status still `pending` after grace period expired
  - Grace period should have expired at `22:36:16` (4 minutes after creation: 3 min week + 1 min grace)
  - Verification at `22:48:38` shows settlement still pending (12 minutes after grace expired)
  - Expected: Automatic settlement should have triggered via `auto-settlement-checker` cron job

**Next Session Tasks:**
1. **Verify Cron Job Status** - Check if `pg_cron` job `auto-settlement-checker` is running and executing
2. **Manually Trigger Settlement** - Use dashboard to manually trigger settlement to verify settlement logic works independently
3. **Fix `week_grace_expires_at`** - Update `rpc_create_commitment` to set `week_grace_expires_at` when creating commitment (currently `null`)
4. **Check Auto-Settlement-Checker Logs** - Review Edge Function logs to see if it's running and what it's finding
5. **Debug Filter Logic** - Verify `auto-settlement-checker` is correctly identifying commitments with expired grace periods

**Remaining Implementation:**
1. Complete automatic settlement debugging (current priority)
2. Phase 7: Testing & Validation (Steps 7.1-7.3)
3. Phase 8: Documentation (Steps 8.1-8.2)

---

**End of Implementation Plan**


