# BackendClient.swift Implementation Plan

## Overview
This document outlines a step-by-step plan for implementing `BackendClient.swift` with the 5 main backend methods. The plan is broken down into small, testable steps to make debugging easier and catch issues early.

---

## Phase 1: Foundation (Minimal, Testable)

### Step 1.1: Basic Structure and Configuration
**Goal:** Create the basic file structure and initialize Supabase client

**Tasks:**
- Create `BackendClient.swift` file
- Add class structure with singleton pattern (`static let shared`)
- Initialize Supabase client using `SupabaseConfig` from `Config.swift`
- Add basic error enum (`BackendError`)

**Test:** Verify the file compiles and client initializes correctly

---

### Step 1.2: Authentication Helpers
**Goal:** Add basic authentication properties

**Tasks:**
- Add `currentSession` computed property (async getter)
- Add `isAuthenticated` computed property (async getter)
- Handle errors gracefully (return `nil` or `false` on failure)

**Test:** Verify properties compile and return expected values

---

## Phase 2: Simplest Method First (Edge Function)

### Step 2.1: Empty Request/Response Structs
**Goal:** Create basic structs for Edge Function calls

**Tasks:**
- Create `EmptyBody` struct (conforms to `Encodable, Sendable`)
- Create `BillingStatusResponse` struct (conforms to `Codable`)
  - Fields: `hasPaymentMethod`, `needsSetupIntent`, `setupIntentClientSecret`, `stripeCustomerId`
  - Add `CodingKeys` enum for snake_case mapping

**Test:** Verify structs compile and conform to required protocols

---

### Step 2.2: First Edge Function - `checkBillingStatus()`
**Goal:** Implement the simplest backend method

**Tasks:**
- Implement `checkBillingStatus()` method
- Call `supabase.functions.invoke("billing-status", ...)`
- Handle response correctly (direct decode from SDK)
- Return `BillingStatusResponse`

**Test:** 
- Verify it compiles
- Verify Supabase SDK API usage is correct
- Check for any isolation issues

---

## Phase 3: RPC Methods (One at a Time)

### Step 3.1: Parameter Structs for First RPC
**Goal:** Create structs for commitment creation

**Tasks:**
- Create `CreateCommitmentParams` struct (conforms to `Encodable, Sendable`)
  - Fields: `weekStartDate`, `limitMinutes`, `penaltyPerMinuteCents`, `appsToLimit`
  - Add `CodingKeys` enum for snake_case mapping
- Create `AppsToLimit` struct (conforms to `Codable, Sendable`)
  - Fields: `appBundleIds`, `categories`
- Create `CommitmentResponse` struct (conforms to `Codable`)
  - Fields: `commitmentId`, `weekStartDate`, `weekEndDate`, `status`, `maxChargeCents`
  - Add `CodingKeys` enum

**Test:** 
- Verify structs compile
- Verify `Sendable` conformance (no MainActor isolation issues)
- Check that all required fields are present

---

### Step 3.2: First RPC - `createCommitment()`
**Goal:** Implement the first RPC method

**Tasks:**
- Implement `createCommitment()` method
- Format dates using `DateFormatter`
- Create parameters struct
- Call `supabase.rpc("create_commitment", params: params).execute()`
- Handle `PostgrestResponse<Void>` return type
- Extract data and decode `CommitmentResponse`
- Handle isolation issues (use `nonisolated` if needed)

**Test:**
- Verify it compiles
- Verify RPC call syntax is correct
- Check for MainActor isolation errors
- Verify response handling is correct

---

### Step 3.3: Second RPC - `reportUsage()`
**Goal:** Implement usage reporting

**Tasks:**
- Create `ReportUsageParams` struct (conforms to `Encodable, Sendable`)
  - Fields: `date`, `weekStartDate`, `usedMinutes`
  - Add `CodingKeys` enum
- Create `UsageReportResponse` struct (conforms to `Codable`)
  - Fields: `date`, `limitMinutes`, `usedMinutes`, `exceededMinutes`, `penaltyCents`, `userWeekTotalCents`, `poolTotalCents`
  - Add `CodingKeys` enum
- Implement `reportUsage()` method
- Handle response correctly

**Test:**
- Verify structs compile
- Verify method compiles
- Check for isolation issues

---

### Step 3.4: Third RPC - `updateMonitoringStatus()`
**Goal:** Implement monitoring status update

**Tasks:**
- Create `UpdateMonitoringStatusParams` struct (conforms to `Encodable, Sendable`)
  - Fields: `commitmentId`, `monitoringStatus`
  - Add `CodingKeys` enum
- Create `MonitoringStatus` enum (conforms to `String, Codable`)
  - Cases: `ok`, `revoked`, `not_granted`
- Implement `updateMonitoringStatus()` method
- Handle void return type correctly

**Test:**
- Verify structs compile
- Verify method compiles
- Check for isolation issues

---

### Step 3.5: Fourth RPC - `getWeekStatus()`
**Goal:** Implement weekly status retrieval

**Tasks:**
- Create `GetWeekStatusParams` struct (conforms to `Encodable, Sendable`)
  - Fields: `weekStartDate`
  - Add `CodingKeys` enum
- Create `WeekStatusResponse` struct (conforms to `Codable`)
  - Fields: `weekStartDate`, `weekEndDate`, `user`, `pool`
  - Add `CodingKeys` enum
- Create nested structs: `UserWeekStatus` and `PoolStatus`
- Implement `getWeekStatus()` method
- Handle nested response decoding

**Test:**
- Verify all structs compile
- Verify method compiles
- Check for isolation issues
- Verify nested decoding works

---

## Phase 4: Admin Method (Optional)

### Step 4.1: Admin Edge Function
**Goal:** Implement admin-only function for testing

**Tasks:**
- Implement `adminCloseWeekNow()` method
- Call `supabase.functions.invoke("admin-close-week-now", ...)`
- Handle void return type

**Test:**
- Verify it compiles
- Verify Edge Function call syntax is correct

---

## Testing Strategy Per Step

For each step, verify:

1. **Compile Check:** Ensure no compilation errors
2. **Type Check:** Verify structs conform to required protocols (`Encodable`, `Sendable`, `Codable`)
3. **Isolation Check:** Verify no MainActor isolation issues (especially for RPC methods)
4. **API Check:** Verify Supabase SDK calls match the actual API

---

## Key Lessons from Previous Attempts

1. **Isolation Issues:** RPC methods may need `nonisolated` annotation to break MainActor isolation
2. **Sendable Conformance:** All parameter structs must conform to `Sendable`
3. **Response Handling:** 
   - Edge Functions can return decoded types directly
   - RPC calls return `PostgrestResponse<Void>` or `PostgrestResponse<SomeType>`
   - Need to extract `.data` from response before decoding
4. **Type Inference:** Swift may have trouble inferring async/throwing in closures, so explicit types help

---

## File Structure

```
Utilities/
├── BackendClient.swift          (Main client class)
├── Config.swift                 (Already exists - Supabase config)
└── ...
```

---

## Next Steps After Implementation

Once all steps are complete and tested:

1. Wire up authentication (Sign in with Apple)
2. Integrate backend calls into existing screens:
   - SetupView → `createCommitment()`
   - MonitorView → `reportUsage()`
   - BulletinView → `getWeekStatus()`
   - AuthorizationView → `updateMonitoringStatus()`
3. Add error handling and user feedback
4. Implement dev-only "Admin Close Week Now" control

---

## Notes

- Each step should be committed separately for easy rollback
- Test compilation after each step before moving to the next
- If isolation issues arise, mark methods as `nonisolated` early
- Keep structs at top level (not nested) for better `Sendable` conformance

