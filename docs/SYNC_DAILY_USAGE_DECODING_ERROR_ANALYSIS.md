# Sync Daily Usage Decoding Error - Analysis

**Date**: 2026-01-15  
**Issue**: `rpc_sync_daily_usage` response decoding fails with type mismatch error

---

## Problem

**Error**:
```
typeMismatch(Swift.String, Swift.DecodingError.Context(
  codingPath: [CodingKeys(stringValue: "processed_weeks", intValue: nil), _CodingKey(stringValue: "Index 0", intValue: 0)], 
  debugDescription: "Expected to decode String but found a dictionary instead."
))
```

**Location**: `BackendClient.swift` line 147 - decoding `processedWeeks`

**Impact**: 
- Sync fails silently (error is caught and logged)
- Daily usage sync doesn't complete
- User doesn't see the error (it's logged but not shown)

---

## Root Cause Analysis

### What the iOS App Expects

**Swift Code** (`BackendClient.swift` line 128, 147):
```swift
let processedWeeks: [String]?  // Expects array of strings

// Decoder:
processedWeeks = try container.decodeIfPresent([String].self, forKey: .processedWeeks)
```

**Expected Format**: `["2026-01-20", "2026-01-27", ...]` (array of date strings)

---

### What the RPC Function Returns

**RPC Function** (`rpc_sync_daily_usage.sql`):

Looking at the SQL draft file, the function returns:
```sql
'processed_weeks', COALESCE((
  SELECT json_agg(json_build_object(
    'week_end_date', uw.week_start_date,
    'total_penalty_cents', uw.total_penalty_cents,
    'needs_reconciliation', uw.needs_reconciliation,
    'reconciliation_delta_cents', uw.reconciliation_delta_cents
  ))
  FROM public.user_week_penalties uw
  WHERE uw.user_id = v_user_id
    AND uw.week_start_date = ANY(v_processed_weeks)
), '[]'::json)
```

**Actual Format**: `[{week_end_date: "...", total_penalty_cents: ..., ...}, ...]` (array of objects)

---

## The Mismatch

**iOS App Expects**:
```json
{
  "processed_weeks": ["2026-01-20", "2026-01-27"]
}
```

**RPC Function Returns**:
```json
{
  "processed_weeks": [
    {
      "week_end_date": "2026-01-20",
      "total_penalty_cents": 1000,
      "needs_reconciliation": false,
      "reconciliation_delta_cents": 0
    },
    {
      "week_end_date": "2026-01-27",
      "total_penalty_cents": 500,
      "needs_reconciliation": true,
      "reconciliation_delta_cents": -200
    }
  ]
}
```

---

## Impact Assessment

### ✅ **Low Impact - Non-Critical**

**Why**:
1. **Sync still works** - The error is caught and logged, but the actual sync operation completes
2. **Data is saved** - Daily usage entries are still inserted/updated in the database
3. **User doesn't see error** - The error is logged but doesn't block the user experience
4. **Navigation works** - User successfully reaches monitor screen

**What's affected**:
- The `processedWeeks` field in the response can't be decoded
- The iOS app can't access reconciliation metadata (but it's not currently used)
- Error is logged but sync continues

---

## Solutions

### Option 1: Update iOS App to Match RPC Response (Recommended)

**Change**: Update `SyncDailyUsageResponse` to decode `processed_weeks` as an array of objects

**Benefits**:
- Matches what the RPC actually returns
- Allows iOS app to access reconciliation metadata in the future
- More accurate representation of the data

**Implementation**:
```swift
struct ProcessedWeek: Codable, Sendable {
    let weekEndDate: String
    let totalPenaltyCents: Int?
    let needsReconciliation: Bool?
    let reconciliationDeltaCents: Int?
    
    enum CodingKeys: String, CodingKey {
        case weekEndDate = "week_end_date"
        case totalPenaltyCents = "total_penalty_cents"
        case needsReconciliation = "needs_reconciliation"
        case reconciliationDeltaCents = "reconciliation_delta_cents"
    }
}

struct SyncDailyUsageResponse: Codable, Sendable {
    // ... existing fields ...
    let processedWeeks: [ProcessedWeek]?  // Changed from [String]?
    
    // Decoder:
    processedWeeks = try container.decodeIfPresent([ProcessedWeek].self, forKey: .processedWeeks)
}
```

---

### Option 2: Update RPC Function to Return Array of Strings

**Change**: Modify `rpc_sync_daily_usage` to return `processed_weeks` as an array of date strings

**Benefits**:
- Simpler response structure
- Matches current iOS app expectations
- Less data transferred

**Drawbacks**:
- Loses reconciliation metadata in response
- Would need separate API call to get reconciliation details

**Implementation**:
```sql
'processed_weeks', (
  SELECT json_agg(week_start_date::text)
  FROM unnest(v_processed_weeks) AS week_start_date
)
```

---

### Option 3: Make processed_weeks Optional and Ignore Decoding Errors

**Change**: Make the decoder more lenient, ignore decoding errors for `processed_weeks`

**Benefits**:
- Quick fix
- Doesn't break existing functionality
- Allows sync to continue

**Drawbacks**:
- Loses access to reconciliation metadata
- Hides the actual issue

**Implementation**:
```swift
// In decoder:
do {
    processedWeeks = try container.decodeIfPresent([String].self, forKey: .processedWeeks)
} catch {
    // Ignore decoding error - processed_weeks is optional
    processedWeeks = nil
    NSLog("SYNC BackendClient: ⚠️ Failed to decode processed_weeks (ignoring): \(error)")
}
```

---

## Recommendation

### ✅ **Option 1: Update iOS App to Match RPC Response**

**Rationale**:
1. **RPC function is correct** - It returns useful reconciliation metadata
2. **Future-proof** - Allows iOS app to use reconciliation data later
3. **Accurate** - Matches actual backend response
4. **Low risk** - `processedWeeks` is optional and not currently used

**Priority**: Medium (not blocking, but should be fixed for accuracy)

---

## Current Status

**What Works**:
- ✅ Payment confirmation
- ✅ Commitment creation
- ✅ Navigation to monitor screen
- ✅ Monitoring started successfully
- ✅ Daily usage sync (data is saved, despite decoding error)

**What's Broken**:
- ⚠️ `processed_weeks` field can't be decoded (but it's optional and not used)

**User Impact**: None - The error is logged but doesn't affect functionality

---

## Conclusion

**The decoding error is non-critical** - The sync operation completes successfully, data is saved, and the user reaches the monitor screen. The error only affects the `processed_weeks` field, which is optional and not currently used by the iOS app.

**Recommended Fix**: Update the iOS app to decode `processed_weeks` as an array of objects (Option 1) to match the actual RPC response and enable future use of reconciliation metadata.



