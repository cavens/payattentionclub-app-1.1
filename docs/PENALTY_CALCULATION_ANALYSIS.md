# Penalty Calculation Analysis

**Date**: 2025-01-01  
**Purpose**: Understand where and how penalties are calculated throughout the system

---

## Overview

There are **TWO separate penalty calculations** in the system:

1. **iOS App Display Penalty** - Calculated locally for UI display (real-time, approximate)
2. **Backend Settlement Penalty** - Calculated on server for actual charges (authoritative, final)

---

## 1. iOS APP DISPLAY PENALTY (For UI Display Only)

### Location
**File**: `payattentionclub-app-1.1/Models/AppModel.swift`  
**Function**: `updateCurrentPenalty()`

### Code
```swift
func updateCurrentPenalty() {
    let usageMinutes = Double(currentUsageSeconds - baselineUsageSeconds) / 60.0
    let limitMinutes = self.limitMinutes
    let excessMinutes = max(0, usageMinutes - limitMinutes)
    currentPenalty = excessMinutes * penaltyPerMinute
}
```

### Formula
```
excessMinutes = max(0, usageMinutes - limitMinutes)
penalty = excessMinutes * penaltyPerMinute
```

### When It's Calculated
- **Real-time** as user uses their device
- Updated when `currentUsageSeconds` changes (from DeviceActivityMonitor extension)
- Used for **display only** in the app UI

### Data Source
- `currentUsageSeconds`: Current total usage from Screen Time API
- `baselineUsageSeconds`: Usage at commitment creation time
- `limitMinutes`: User's daily limit
- `penaltyPerMinute`: User's penalty rate (e.g., $0.10/minute)

### Purpose
- Show user their **current penalty** in real-time
- Display in `BulletinView` and `MonitorView`
- **NOT used for actual charges** - just for user awareness

### Display Logic
**File**: `payattentionclub-app-1.1/Views/BulletinView.swift`

```swift
private var weekPenaltyDollars: Double {
    if let weekStatus = model.weekStatus, weekStatus.userTotalPenaltyCents > 0 {
        // Use backend penalty if available (authoritative)
        return Double(weekStatus.userTotalPenaltyCents) / 100.0
    }
    // Fallback to calculated penalty (for display only)
    return model.currentPenalty
}
```

**Priority**: Backend penalty > Calculated penalty (if backend not available)

---

## 2. BACKEND SETTLEMENT PENALTY (For Actual Charges)

### Location
**File**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`  
**Lines**: 76-77, 129-136

### Calculation Flow

#### Step 1: Daily Penalty Calculation (Per Day)
**Location**: `rpc_sync_daily_usage.sql` lines 76-77

```sql
v_exceeded_minutes := GREATEST(0, v_used_minutes - v_limit_minutes);
v_penalty_cents := v_exceeded_minutes * v_penalty_per_minute_cents;
```

**Formula**:
```
exceeded_minutes = max(0, used_minutes - limit_minutes)
penalty_cents = exceeded_minutes * penalty_per_minute_cents
```

**Stored in**: `daily_usage` table
- `exceeded_minutes`: Minutes over limit for this day
- `penalty_cents`: Penalty for this day (in cents)

#### Step 2: Weekly Total Penalty (Sum of All Days)
**Location**: `rpc_sync_daily_usage.sql` lines 129-136

```sql
SELECT COALESCE(SUM(penalty_cents), 0)
INTO v_user_week_total_cents
FROM public.daily_usage du
JOIN public.commitments c ON du.commitment_id = c.id
WHERE du.user_id = v_user_id
  AND c.week_end_date = v_week
  AND du.date >= c.week_start_date
  AND du.date <= c.week_end_date;
```

**Formula**:
```
total_penalty_cents = SUM(all daily penalty_cents for the week)
```

**Stored in**: `user_week_penalties` table
- `total_penalty_cents`: Total penalty for the entire week
- This is the **authoritative** penalty used for settlement

### When It's Calculated

#### Scenario A: User Syncs Before Tuesday Noon
1. User opens app → `UsageSyncManager.syncToBackend()` called
2. App sends `DailyUsageEntry` objects to backend
3. Backend calls `rpc_sync_daily_usage`
4. For each day:
   - Calculates `exceeded_minutes` and `penalty_cents`
   - Stores in `daily_usage` table
5. After all days processed:
   - Sums all `penalty_cents` from `daily_usage`
   - Stores total in `user_week_penalties.total_penalty_cents`
6. Tuesday 12:00 ET: Settlement uses `total_penalty_cents` for charge

#### Scenario B: User Doesn't Sync
- No `daily_usage` rows created
- `user_week_penalties.total_penalty_cents` = 0 (or doesn't exist)
- Tuesday 12:00 ET: Settlement charges worst case (`max_charge_cents`)

#### Scenario C: User Syncs After Tuesday Noon (Late Sync)
1. Same as Scenario A (calculates daily and weekly totals)
2. Backend detects previous settlement
3. Calculates reconciliation delta:
   ```sql
   v_reconciliation_delta := v_capped_actual_cents - COALESCE(v_prev_charged_amount, 0);
   ```
4. Flags for reconciliation if delta ≠ 0

---

## 3. DATA FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────┐
│ iOS APP (Display Only)                                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  DeviceActivityMonitor Extension                            │
│  └─> Tracks usage in real-time                              │
│      └─> Updates currentUsageSeconds                        │
│                                                              │
│  AppModel.updateCurrentPenalty()                            │
│  └─> Calculates: excessMinutes * penaltyPerMinute           │
│      └─> Stores in: currentPenalty (for display)            │
│                                                              │
│  BulletinView / MonitorView                                 │
│  └─> Displays: currentPenalty (or backend penalty)        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ User opens app
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ SYNC PROCESS                                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  UsageSyncManager.syncToBackend()                           │
│  └─> Reads DailyUsageEntry from App Group                   │
│      └─> Sends to: BackendClient.syncDailyUsage()           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTP Request
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BACKEND (Authoritative Calculation)                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  rpc_sync_daily_usage()                                      │
│  │                                                           │
│  ├─> For each day:                                           │
│  │   ├─> Get limit_minutes, penalty_per_minute_cents        │
│  │   │   from commitments table                              │
│  │   ├─> Calculate: exceeded_minutes = used - limit          │
│  │   ├─> Calculate: penalty_cents = exceeded * rate         │
│  │   └─> Store in: daily_usage table                        │
│  │                                                           │
│  └─> After all days:                                         │
│      ├─> SUM(penalty_cents) from daily_usage                │
│      └─> Store in: user_week_penalties.total_penalty_cents  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Tuesday 12:00 ET
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ SETTLEMENT                                                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  bright-service/run-weekly-settlement                        │
│  └─> Reads: user_week_penalties.total_penalty_cents         │
│      └─> Caps at: max_charge_cents (authorization)         │
│          └─> Charges: MIN(total_penalty, authorization)    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. KEY DIFFERENCES

| Aspect | iOS App Display | Backend Settlement |
|--------|----------------|-------------------|
| **Location** | `AppModel.swift` | `rpc_sync_daily_usage.sql` |
| **When** | Real-time (as user uses device) | When user syncs to server |
| **Formula** | `excessMinutes * penaltyPerMinute` | Same formula, but per day |
| **Data Source** | `currentUsageSeconds - baselineUsageSeconds` | `daily_usage` table rows |
| **Granularity** | Total usage (not per day) | Per day, then summed |
| **Purpose** | UI display only | Actual charges |
| **Authoritative** | ❌ No (approximate) | ✅ Yes (final) |
| **Used for Settlement** | ❌ No | ✅ Yes |

---

## 5. WHY TWO CALCULATIONS?

### iOS App Calculation (Display)
- **Purpose**: Show user real-time feedback
- **Advantage**: Instant updates, no network required
- **Limitation**: May not match backend exactly (timing, rounding)

### Backend Calculation (Settlement)
- **Purpose**: Authoritative source of truth for charges
- **Advantage**: Consistent, auditable, per-day granularity
- **Requirement**: User must sync for this to be calculated

---

## 6. CRITICAL POINTS

### Point 1: Daily Granularity
- **Backend** calculates penalty **per day**, then sums
- **iOS app** calculates penalty from **total usage**
- This can cause minor discrepancies

### Point 2: Baseline Handling
- **iOS app**: Uses `baselineUsageSeconds` (usage at commitment creation)
- **Backend**: Uses `used_minutes` (already baseline-adjusted by extension)
- Extension writes: `usedMinutes = max(0, totalMinutes - baselineMinutes)`

### Point 3: Source of Truth
- **Backend `user_week_penalties.total_penalty_cents`** is the authoritative value
- iOS app display is **informational only**
- Settlement always uses backend value

### Point 4: When Backend Calculation Happens
- **Only when user syncs** (opens app and syncs to backend)
- If user never syncs, backend has no `daily_usage` rows
- Settlement then charges worst case (`max_charge_cents`)

---

## 7. FORMULA COMPARISON

### iOS App (Display)
```
usageMinutes = (currentUsageSeconds - baselineUsageSeconds) / 60.0
excessMinutes = max(0, usageMinutes - limitMinutes)
penalty = excessMinutes * penaltyPerMinute
```

### Backend (Settlement)
```
For each day:
  exceeded_minutes = max(0, used_minutes - limit_minutes)
  penalty_cents = exceeded_minutes * penalty_per_minute_cents
  Store in daily_usage table

For the week:
  total_penalty_cents = SUM(penalty_cents) from daily_usage
  Store in user_week_penalties.total_penalty_cents
```

**Note**: Formulas are the same, but backend does it per day for accuracy.

---

## 8. WHERE ACTUAL CHARGE AMOUNT COMES FROM

### Settlement Process
1. **Read**: `user_week_penalties.total_penalty_cents` (from backend calculation)
2. **Get**: `commitments.max_charge_cents` (authorization amount)
3. **Calculate**: `charge_amount = MIN(total_penalty_cents, max_charge_cents)`
4. **Charge**: Stripe PaymentIntent with `charge_amount`

**Location**: `supabase/functions/bright-service/run-weekly-settlement.ts`

```typescript
function getChargeAmount(candidate: SettlementCandidate, type: ChargeType): number {
  if (type === "actual") {
    const actual = getActualPenaltyCents(candidate); // From user_week_penalties.total_penalty_cents
    const maxCharge = getWorstCaseAmountCents(candidate); // From commitments.max_charge_cents
    return Math.min(actual, maxCharge); // Cap at authorization
  }
  return getWorstCaseAmountCents(candidate); // Worst case if no sync
}
```

---

## 9. SUMMARY

### iOS App Penalty (Display)
- **Where**: `AppModel.updateCurrentPenalty()`
- **When**: Real-time as user uses device
- **Purpose**: Show user their current penalty
- **Not used for**: Actual charges

### Backend Penalty (Settlement)
- **Where**: `rpc_sync_daily_usage.sql`
- **When**: When user syncs to server
- **Purpose**: Authoritative penalty for charges
- **Used for**: Settlement charges (capped at authorization)

### Actual Charge Amount
- **Source**: `user_week_penalties.total_penalty_cents` (backend calculation)
- **Capped at**: `commitments.max_charge_cents` (authorization)
- **Formula**: `MIN(total_penalty_cents, max_charge_cents)`

---

## 10. POTENTIAL ISSUES TO CHECK

1. **Discrepancy between iOS display and backend calculation**
   - iOS uses total usage, backend uses per-day
   - Minor differences possible due to rounding/timing

2. **Baseline handling consistency**
   - Ensure extension correctly calculates `usedMinutes = total - baseline`
   - Backend should receive already-adjusted values

3. **Daily usage entries**
   - Extension must create `DailyUsageEntry` objects correctly
   - Must include correct `weekStartDate` (deadline date)

4. **Sync timing**
   - If user never syncs, backend has no penalty data
   - Settlement will charge worst case

---

**End of Analysis**


