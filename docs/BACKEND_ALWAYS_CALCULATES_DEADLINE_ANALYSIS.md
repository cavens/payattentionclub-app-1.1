# Backend Always Calculates Deadline - What Would Break?

**Date**: 2026-01-15  
**Purpose**: Analyze what would break if backend always calculates deadline (single source of truth)

---

## The Question

**Why can't we just make the backend always calculate the deadline in both testing and normal mode? What would break in the frontend?**

---

## Current Usage of Deadline in iOS App

### 1. **Preview Max Charge** (BEFORE committing)

**Location**: `SetupView.swift` and `AuthorizationView.swift`

**Flow**:
1. User sets up commitment (limit, penalty, apps)
2. iOS app calculates deadline: `model.getNextMondayNoonEST()`
3. iOS app calls `previewMaxCharge(deadlineDate: deadline, ...)` 
4. Backend returns max charge amount
5. iOS app displays authorization amount to user
6. User sees amount and decides to commit
7. iOS app calls `createCommitment(weekStartDate: deadline, ...)`

**Code**:
```swift
// SetupView.swift - Calculates deadline for preview
let deadline = model.getNextMondayNoonEST()
let preview = try await BackendClient.shared.previewMaxCharge(
    deadlineDate: deadline,  // ⚠️ Needs deadline BEFORE committing
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps
)
```

**Why it needs deadline**: The max charge calculation depends on the deadline (how many days until deadline × limit × penalty × apps).

---

### 2. **Create Commitment** (AFTER user commits)

**Location**: `AuthorizationView.swift`

**Flow**:
1. User taps "Lock in" button
2. iOS app calculates deadline: `model.getNextMondayNoonEST()`
3. iOS app calls `createCommitment(weekStartDate: deadline, ...)`
4. Backend uses deadline (normal mode) or overrides it (testing mode)
5. Backend returns deadline in response
6. iOS app uses backend deadline (after the fix)

**Code**:
```swift
// AuthorizationView.swift - Calculates deadline for commitment
let weekStartDate = await MainActor.run { model.getNextMondayNoonEST() }
let commitmentResponse = try await BackendClient.shared.createCommitment(
    weekStartDate: weekStartDate,  // ⚠️ Currently required parameter
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps,
    savedPaymentMethodId: savedPaymentMethodId
)
```

---

## What Would Break If Backend Always Calculates?

### ❌ **Preview Max Charge Would Break**

**Current**:
```swift
// iOS app calculates deadline
let deadline = model.getNextMondayNoonEST()

// Calls preview with deadline
let preview = try await BackendClient.shared.previewMaxCharge(
    deadlineDate: deadline,  // ⚠️ Required parameter
    ...
)
```

**If backend always calculates**:
- iOS app doesn't have deadline yet
- Can't call `previewMaxCharge(deadlineDate: ...)` 
- **Preview would break** ❌

**Solution Options**:

**Option A: Remove deadline from previewMaxCharge**
```swift
// Backend calculates deadline internally
let preview = try await BackendClient.shared.previewMaxCharge(
    // No deadlineDate parameter
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps
)
```

**Backend changes needed**:
- `rpc_preview_max_charge` calculates deadline internally (next Monday 12:00 ET)
- Testing mode: Uses compressed deadline (3 minutes)
- Normal mode: Uses next Monday 12:00 ET

**Pros**:
- ✅ Single source of truth (backend calculates)
- ✅ Consistent with commitment creation
- ✅ No iOS app deadline calculation needed

**Cons**:
- ⚠️ Breaking change (API change)
- ⚠️ Requires iOS app update
- ⚠️ Backend must handle timezone

---

**Option B: Add "get deadline" endpoint**
```swift
// Step 1: Get deadline from backend
let deadlineResponse = try await BackendClient.shared.getDeadline()
let deadline = deadlineResponse.deadline

// Step 2: Use deadline for preview
let preview = try await BackendClient.shared.previewMaxCharge(
    deadlineDate: deadline,
    ...
)
```

**Backend changes needed**:
- New endpoint: `getDeadline()` returns deadline
- Testing mode: Returns compressed deadline (3 minutes from now)
- Normal mode: Returns next Monday 12:00 ET

**Pros**:
- ✅ Single source of truth (backend calculates)
- ✅ Preview API unchanged
- ✅ Consistent deadline

**Cons**:
- ⚠️ Extra API call (performance impact)
- ⚠️ Requires iOS app update
- ⚠️ More complex flow

---

### ✅ **Create Commitment Would Work**

**Current**:
```swift
let weekStartDate = model.getNextMondayNoonEST()
let commitmentResponse = try await BackendClient.shared.createCommitment(
    weekStartDate: weekStartDate,  // ⚠️ Currently required
    ...
)
```

**If backend always calculates**:
```swift
// No deadline parameter needed
let commitmentResponse = try await BackendClient.shared.createCommitment(
    // No weekStartDate parameter
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps,
    savedPaymentMethodId: savedPaymentMethodId
)
```

**Backend changes needed**:
- Remove `weekStartDate` parameter from `createCommitment()`
- Backend calculates deadline internally:
  - Testing mode: `now + 3 minutes`
  - Normal mode: `next Monday 12:00 ET`
- Return deadline in response (already does this)

**Pros**:
- ✅ Single source of truth (backend calculates)
- ✅ Consistent with testing mode
- ✅ Simpler iOS app (no deadline calculation)

**Cons**:
- ⚠️ Breaking change (API change)
- ⚠️ Requires iOS app update

---

## Summary: What Would Break?

### ❌ **Preview Max Charge**

**Problem**: iOS app needs deadline to call `previewMaxCharge(deadlineDate: ...)`

**Solutions**:
1. **Remove deadline parameter** from `previewMaxCharge` (backend calculates internally)
2. **Add "get deadline" endpoint** (iOS app calls it first)

**Recommendation**: **Option 1** (remove deadline parameter) - simpler, single source of truth

---

### ✅ **Create Commitment**

**Would work fine** - just remove `weekStartDate` parameter, backend calculates internally

---

## Implementation Plan

### Step 1: Update Preview API

**Backend** (`rpc_preview_max_charge`):
```sql
-- Remove p_deadline_date parameter
-- Calculate deadline internally:
--   Testing mode: now + 3 minutes
--   Normal mode: next Monday 12:00 ET
```

**iOS App** (`BackendClient.swift`):
```swift
// Remove deadlineDate parameter
func previewMaxCharge(
    // No deadlineDate parameter
    limitMinutes: Int,
    penaltyPerMinuteCents: Int,
    selectedApps: FamilyActivitySelection
) async throws -> MaxChargePreviewResponse
```

**iOS App** (`SetupView.swift`):
```swift
// Remove deadline calculation
let preview = try await BackendClient.shared.previewMaxCharge(
    // No deadlineDate
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps
)
```

---

### Step 2: Update Commitment API

**Backend** (`super-service/index.ts`):
```typescript
// Remove weekStartDate parameter
// Always calculate deadline:
if (TESTING_MODE) {
  deadlineDateForRPC = formatDeadlineDate(getNextDeadline()).split('T')[0];
  deadlineTimestampForRPC = formatDeadlineDate(getNextDeadline());
} else {
  deadlineDateForRPC = formatDeadlineDate(calculateNextMondayNoonET()).split('T')[0];
  deadlineTimestampForRPC = null;
}
```

**iOS App** (`BackendClient.swift`):
```swift
// Remove weekStartDate parameter
func createCommitment(
    // No weekStartDate parameter
    limitMinutes: Int,
    penaltyPerMinuteCents: Int,
    selectedApps: FamilyActivitySelection,
    savedPaymentMethodId: String? = nil
) async throws -> CommitmentResponse
```

**iOS App** (`AuthorizationView.swift`):
```swift
// Remove deadline calculation
let commitmentResponse = try await BackendClient.shared.createCommitment(
    // No weekStartDate
    limitMinutes: limitMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    selectedApps: selectedApps,
    savedPaymentMethodId: savedPaymentMethodId
)
```

---

## Conclusion

### What Would Break?

**Preview Max Charge** ❌ - Currently requires deadline parameter

**Solution**: Remove deadline parameter, backend calculates internally

### What Would Work?

**Create Commitment** ✅ - Just remove deadline parameter

### Benefits of Making Backend Always Calculate

1. ✅ **Single source of truth** (backend always calculates)
2. ✅ **Consistent behavior** (same logic in both modes)
3. ✅ **Simpler iOS app** (no deadline calculation needed)
4. ✅ **Easier maintenance** (one place to change deadline logic)

### Trade-offs

1. ⚠️ **Breaking changes** (API changes, iOS app update required)
2. ⚠️ **Backend must handle timezone** (currently iOS app does)
3. ⚠️ **Preview API change** (remove deadline parameter)

### Recommendation

**Yes, we can make backend always calculate!** The only thing that would break is `previewMaxCharge` requiring a deadline parameter, but we can fix that by removing the parameter and having the backend calculate it internally.

This would give us:
- ✅ Single source of truth
- ✅ Consistent behavior
- ✅ Simpler iOS app

The changes are straightforward:
1. Remove `deadlineDate` parameter from `previewMaxCharge`
2. Remove `weekStartDate` parameter from `createCommitment`
3. Backend calculates deadline internally in both functions



