# Backend Always Calculates Deadline - Risk Analysis

**Date**: 2026-01-15  
**Purpose**: Analyze risks of making backend always calculate deadlines (single source of truth)

---

## Current State

### ✅ **Backend Already Calculates Max Charge**

**Flow**:
1. iOS app calculates deadline: `getNextMondayNoonEST()`
2. iOS app calls `previewMaxCharge(deadlineDate: deadline, ...)`
3. **Backend calculates max charge** using `calculate_max_charge_cents()`
4. Backend returns amount

**The Problem**: iOS app still calculates deadline locally and passes it to backend.

---

## Proposed Change

### Make Backend Always Calculate Deadline

**Changes Needed**:

1. **Remove `deadlineDate` parameter from `previewMaxCharge()`**
   - Backend calculates deadline internally
   - Testing mode: `now + 3 minutes`
   - Normal mode: `next Monday 12:00 ET`

2. **Remove `weekStartDate` parameter from `createCommitment()`**
   - Backend calculates deadline internally
   - Testing mode: `now + 3 minutes`
   - Normal mode: `next Monday 12:00 ET`

3. **Update iOS app** to remove deadline calculations

---

## Risk Analysis

### ✅ **Low Risk: Preview Max Charge**

**Current**:
```swift
let deadline = getNextMondayNoonEST()
let preview = try await BackendClient.shared.previewMaxCharge(
    deadlineDate: deadline,  // iOS calculates
    ...
)
```

**Proposed**:
```swift
let preview = try await BackendClient.shared.previewMaxCharge(
    // No deadline parameter - backend calculates
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps
)
```

**Risks**:
- ✅ **Low**: Backend already calculates max charge amount
- ✅ **Low**: Deadline calculation is straightforward (next Monday 12:00 ET)
- ✅ **Low**: Testing mode already works (backend calculates compressed deadline)
- ⚠️ **Medium**: Preview and commitment might use different deadlines if called at different times

**Mitigation**:
- Backend uses same deadline calculation logic for both preview and commitment
- In testing mode, both use `getNextDeadline()` (3 minutes from now)
- In normal mode, both use `calculateNextMondayNoonET()` (next Monday 12:00 ET)

---

### ⚠️ **Medium Risk: Timing Window Between Preview and Commitment**

**Scenario**:
1. User views preview at 11:59 AM ET on Monday
2. Backend calculates deadline: Monday 12:00 ET (1 minute away)
3. User takes 2 minutes to decide
4. User commits at 12:01 PM ET on Monday
5. Backend calculates deadline: **Next Monday 12:00 ET** (7 days away)

**Problem**: Preview showed amount for Monday deadline, but commitment uses next Monday deadline.

**Impact**:
- ⚠️ **Medium**: Authorization amount might be different
- ⚠️ **Medium**: User might see different amount than preview
- ⚠️ **Low**: User experience confusion

**Mitigation Options**:

**Option A: Accept the difference**
- Preview is just an estimate
- Actual commitment uses current time's deadline
- User sees correct amount when committing

**Option B: Cache deadline in session**
- Backend returns deadline in preview response
- iOS app stores deadline
- Commitment uses cached deadline if within X minutes
- **Complexity**: Medium (requires session management)

**Option C: Use "commitment window"**
- If preview was called within last 5 minutes, use same deadline
- Otherwise, recalculate
- **Complexity**: Medium (requires tracking preview time)

**Recommendation**: **Option A** (accept the difference) - simplest, preview is just an estimate anyway.

---

### ✅ **Low Risk: Testing Mode**

**Current**:
- Backend already calculates compressed deadline in testing mode
- Works correctly

**Proposed**:
- Same behavior, just removes deadline parameter
- **No risk** - already working

---

### ⚠️ **Medium Risk: API Breaking Changes**

**Changes Required**:

1. **`rpc_preview_max_charge`**:
   - Remove `p_deadline_date` parameter
   - Calculate deadline internally

2. **`super-service` Edge Function**:
   - Remove `weekStartDate` parameter from request
   - Calculate deadline internally

3. **iOS App**:
   - Remove deadline calculations
   - Update API calls

**Risks**:
- ⚠️ **Medium**: Breaking change - requires coordinated deployment
- ⚠️ **Medium**: Old iOS app versions won't work with new backend
- ⚠️ **Low**: Migration path needed (support both old and new API temporarily)

**Mitigation**:
- Deploy backend changes first (support both old and new API)
- Deploy iOS app update
- Remove old API support after iOS app is updated

---

### ✅ **Low Risk: Timezone Handling**

**Current**:
- iOS app handles timezone (calculates in ET)
- Backend receives date and converts to ET

**Proposed**:
- Backend handles timezone (calculates in ET)
- **No risk** - backend already has timezone logic

**Code**:
```typescript
// Backend already has timezone logic
const TIME_ZONE = "America/New_York";
function toDateInTimeZone(date: Date, timeZone: string): Date {
  return new Date(date.toLocaleString("en-US", { timeZone }));
}
```

---

### ⚠️ **Low Risk: DST Transitions**

**Current**:
- iOS app calculates deadline (handles DST)
- Backend uses date and converts to ET

**Proposed**:
- Backend calculates deadline (handles DST)
- **Low risk** - backend already has DST-aware logic

**Note**: DST fix (from earlier analysis) applies to grace period, not deadline calculation. Deadline calculation is simpler (just "next Monday 12:00 ET").

---

### ✅ **Low Risk: Edge Cases**

**Edge Cases to Consider**:

1. **User previews at 11:59 AM Monday, commits at 12:01 PM Monday**
   - Preview: Monday 12:00 ET (1 minute away)
   - Commitment: Next Monday 12:00 ET (7 days away)
   - **Risk**: Low (preview is estimate, commitment is actual)

2. **User previews in testing mode, commits in normal mode**
   - Preview: 3 minutes from now
   - Commitment: Next Monday 12:00 ET
   - **Risk**: Low (testing mode is separate environment)

3. **Backend timezone vs user's device timezone**
   - Backend always uses ET
   - **Risk**: Low (consistent behavior)

4. **Network delay between preview and commitment**
   - Preview at 11:59:58, commitment at 12:00:02
   - **Risk**: Low (2-second window is acceptable)

---

## Benefits vs Risks

### ✅ **Benefits**

1. ✅ **Single source of truth** (backend always calculates)
2. ✅ **Consistent behavior** (same logic in both modes)
3. ✅ **Simpler iOS app** (no deadline calculation needed)
4. ✅ **Easier maintenance** (one place to change deadline logic)
5. ✅ **Testing mode works automatically** (backend knows about TESTING_MODE)

### ⚠️ **Risks**

1. ⚠️ **Timing window** (preview and commitment might use different deadlines)
   - **Mitigation**: Accept the difference (preview is estimate)
   - **Severity**: Medium
   - **Likelihood**: Low (only if user takes >1 minute to decide)

2. ⚠️ **API breaking changes** (requires coordinated deployment)
   - **Mitigation**: Support both old and new API temporarily
   - **Severity**: Medium
   - **Likelihood**: High (definitely happens during migration)

3. ⚠️ **Edge cases** (DST, timezone, timing windows)
   - **Mitigation**: Backend already handles these correctly
   - **Severity**: Low
   - **Likelihood**: Low

---

## Recommendation

### ✅ **Proceed with Change**

**Rationale**:
1. **Benefits outweigh risks** - Single source of truth is valuable
2. **Risks are manageable** - Timing window is acceptable (preview is estimate)
3. **Backend already handles complexity** - Timezone, DST, testing mode all work
4. **Consistency is important** - Same behavior in both modes

**Implementation Strategy**:

1. **Phase 1: Backend Support Both APIs**
   - Add new API (no deadline parameter)
   - Keep old API working (backward compatibility)
   - Deploy backend

2. **Phase 2: iOS App Update**
   - Update to use new API (no deadline parameter)
   - Deploy iOS app

3. **Phase 3: Remove Old API**
   - Remove deadline parameter support
   - Clean up code

**Timeline**:
- Phase 1: 1-2 days (backend changes)
- Phase 2: 1-2 days (iOS app changes)
- Phase 3: 1 day (cleanup)

**Total**: ~1 week for full migration

---

## Conclusion

### Risk Level: **LOW to MEDIUM**

**Main Risks**:
1. ⚠️ **Timing window** between preview and commitment (acceptable - preview is estimate)
2. ⚠️ **API breaking changes** (manageable with phased rollout)

**Benefits**:
1. ✅ **Single source of truth** (valuable for maintenance)
2. ✅ **Consistent behavior** (same logic everywhere)
3. ✅ **Simpler iOS app** (less code to maintain)

### Recommendation: **PROCEED**

The benefits of having a single source of truth outweigh the risks. The main risk (timing window) is acceptable because preview is just an estimate, and the actual commitment will use the correct deadline.

**Next Steps**:
1. Implement backend changes (support both APIs)
2. Update iOS app to use new API
3. Remove old API support



