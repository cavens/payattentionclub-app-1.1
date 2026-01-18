# Testing Mode vs Normal Mode: Understanding
**Date**: 2026-01-17  
**Purpose**: Confirm understanding of differences between testing and normal mode

---

## Normal Mode Timeline

### Week Period
- **Start**: Monday 12:00 PM Eastern Time
- **End**: Next Monday 12:00 PM Eastern Time (7 days later)
- **Duration**: 7 days
- **Fixed Schedule**: Always Monday to Monday, regardless of when commitment is created

### Tracking Period
- **Active Tracking**: From Monday noon ET to next Monday noon ET
- **At Next Monday Noon ET**: **Stop tracking** for that previous week
- **Deadline**: `week_end_date` = Next Monday date
- **Deadline Timestamp**: Monday 12:00 PM ET (calculated from `week_end_date`)

### Grace Period
- **Start**: Monday 12:00 PM ET (when tracking stops)
- **End**: Tuesday 12:00 PM ET (24 hours later)
- **Duration**: 24 hours
- **Purpose**: Give users time to sync their usage data

### Settlement
- **When**: Tuesday 12:00 PM ET (after grace period expires)
- **Trigger**: Cron job (scheduled for Tuesday 12:00 PM ET)
- **Logic**:
  - If user synced data → Charge actual penalty (capped at max_charge_cents)
  - If user didn't sync → Charge max_charge_cents (worst case)

### Reconciliation
- **When**: After Tuesday 12:00 PM ET (after settlement)
- **Trigger**: When user opens app and syncs data after settlement
- **Logic**:
  - Calculate reconciliation delta (actual vs charged)
  - If delta < 0: Refund difference
  - If delta > 0: Charge additional amount

---

## Testing Mode Timeline

### Week Period
- **Start**: When commitment is created (dynamic, not fixed)
- **End**: 3 minutes after commitment creation
- **Duration**: 3 minutes (always)
- **Dynamic Schedule**: Each commitment has its own timeline based on creation time

### Tracking Period
- **Active Tracking**: From commitment creation to 3 minutes later
- **At 3 Minutes After Creation**: **Stop tracking** for that commitment
- **Deadline**: `week_end_timestamp` = creation_time + 3 minutes (precise timestamp)
- **Deadline Date**: `week_end_date` = UTC date of deadline (for querying)

### Grace Period
- **Start**: 3 minutes after creation (when tracking stops)
- **End**: 4 minutes after creation (1 minute later)
- **Duration**: 1 minute (instead of 24 hours)
- **Purpose**: Give users time to sync their usage data (compressed timeline)

### Settlement
- **When**: 4 minutes after commitment creation (after grace period expires)
- **Trigger**: Cron job (runs every 1-2 minutes, checks if grace period expired)
- **Logic**:
  - If user synced data → Charge actual penalty (capped at max_charge_cents)
  - If user didn't sync → Charge max_charge_cents (worst case)
- **Note**: Cron job must run frequently (every 1-2 minutes) to catch grace period expiration

### Reconciliation
- **When**: After 4 minutes after creation (after settlement)
- **Trigger**: When user opens app and syncs data after settlement
- **Logic**:
  - Calculate reconciliation delta (actual vs charged)
  - If delta < 0: Refund difference
  - If delta > 0: Charge additional amount

---

## Key Differences

| Aspect | Normal Mode | Testing Mode |
|--------|-------------|--------------|
| **Period Start** | Fixed: Monday 12:00 ET | Dynamic: Commitment creation time |
| **Period Duration** | 7 days | 3 minutes |
| **Period End** | Next Monday 12:00 ET | Creation time + 3 minutes |
| **Grace Period** | 24 hours | 1 minute |
| **Grace Period End** | Tuesday 12:00 ET | Creation time + 4 minutes |
| **Settlement Time** | Tuesday 12:00 ET (fixed) | Creation time + 4 minutes (dynamic) |
| **Cron Job Schedule** | Once per week (Tuesday 12:00 ET) | Every 1-2 minutes (checks all commitments) |
| **Deadline Storage** | `week_end_date` (date only) | `week_end_timestamp` (precise timestamp) |

---

## Settlement Cron Job Requirements

### Normal Mode
- **Schedule**: Once per week (Tuesday 12:00 PM ET)
- **Logic**: Process all commitments with `week_end_date` = previous Monday
- **Timing**: Fixed schedule, runs at specific time

### Testing Mode
- **Schedule**: Every 1-2 minutes (frequent polling)
- **Logic**: 
  1. Find all commitments where grace period has expired
  2. Check `week_end_timestamp` + 1 minute <= now
  3. Process those commitments
- **Timing**: Dynamic, must check each commitment's individual deadline

---

## Reconciliation Requirements

### Both Modes
- **Trigger**: User opens app and syncs data after settlement
- **Logic**: Same reconciliation logic (calculate delta, refund or charge)
- **Difference**: Only timing (24 hours vs 1 minute grace period)

---

## Current Implementation Status

### ✅ What's Working
1. **Timing Helper** (`_shared/timing.ts`):
   - Correctly calculates 3 minutes vs 7 days
   - Correctly calculates 1 minute vs 24 hours grace period

2. **Deadline Calculation**:
   - Testing mode: Uses `week_end_timestamp` (precise)
   - Normal mode: Uses `week_end_date` (Monday calculation)

3. **Settlement Logic**:
   - Same business logic for both modes
   - Uses `getGraceDeadline()` which handles both modes

### ⚠️ What's Missing
1. **Settlement Cron Job for Testing Mode**:
   - Normal mode: Has cron job (Tuesday 12:00 ET)
   - Testing mode: **Missing** cron job (should run every 1-2 minutes)

2. **Cron Job Logic**:
   - Must check each commitment's individual `week_end_timestamp`
   - Must calculate if grace period expired for each commitment
   - Cannot use fixed schedule (each commitment has different deadline)

---

## Confirmation

### Your Understanding is ✅ **CORRECT**

**Normal Mode**:
- Fixed period: Monday noon ET to next Monday noon ET
- Stop tracking at next Monday noon ET
- 24-hour grace period (Monday noon to Tuesday noon ET)
- Settlement at Tuesday noon ET (via cron job)
- Reconciliation after Tuesday noon if user syncs

**Testing Mode**:
- Dynamic period: Starts when commitment created, always 3 minutes
- Stop tracking at 3 minutes after creation
- 1-minute grace period (3 minutes to 4 minutes after creation)
- Settlement after 1-minute grace period (via cron job running every 1-2 minutes)
- Reconciliation after grace period if user syncs

**Key Point**: Testing mode needs a **frequent cron job** (every 1-2 minutes) that checks if each commitment's grace period has expired, rather than a fixed schedule.


