# Step 2.1 iOS Testing Guide

**Step**: 2.1 - Update AuthorizationView to Use Backend Deadline  
**Purpose**: Verify iOS app uses backend deadline (compressed in testing mode)

---

## Prerequisites

1. **Xcode** installed and configured
2. **iOS Simulator** or physical device
3. **Backend deployed** (staging environment)
4. **Test user** with payment method set up

---

## Testing Approach

### Option 1: Manual Testing via iOS App (Recommended)

**Steps**:

1. **Build and Run iOS App**
   ```bash
   # Open Xcode
   open payattentionclub-app-1.1.xcodeproj
   
   # Or build from command line
   xcodebuild -project payattentionclub-app-1.1.xcodeproj \
     -scheme payattentionclub-app-1.1 \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     build
   ```

2. **Enable Console Logging**
   - In Xcode: View → Debug Area → Activate Console (or Cmd+Shift+Y)
   - Filter logs by: "AUTH AuthorizationView" or "deadline"

3. **Create Commitment**
   - Open app
   - Select apps to limit
   - Set limit and penalty
   - Tap "Lock in" button
   - Watch console logs

4. **Check Logs for Backend Deadline**
   - Look for: `"AUTH AuthorizationView: ✅ Using backend deadline: [date]"`
   - Verify: `"deadlineDate from backend: [date]"`

5. **Verify Countdown Display**
   - After commitment creation, check countdown timer
   - Normal mode: Should show next Monday (e.g., "4d 12h 30m 15s")
   - Testing mode: Should show ~3 minutes (e.g., "0d 0h 3m 0s")

---

### Option 2: Testing Mode Verification

**Setup**:
1. Deploy backend with `TESTING_MODE=true`
2. Build and run iOS app

**Steps**:
1. **Create Commitment**
   - Select apps, set limits, lock in

2. **Check Logs**
   ```
   LOCKIN AuthorizationView: deadlineDate from backend: 2025-12-31
   AUTH AuthorizationView: ✅ Using backend deadline: 2025-12-31 12:00:00 -0500 (from 2025-12-31)
   ```

3. **Verify Countdown**
   - Should show approximately 3 minutes
   - Countdown should match backend deadline

4. **Verify Deadline Storage**
   - Check `UsageTracker.shared.getCommitmentDeadline()`
   - Should return date ~3 minutes from now

---

### Option 3: Normal Mode Verification

**Setup**:
1. Ensure backend has `TESTING_MODE=false` (or not set)
2. Build and run iOS app

**Steps**:
1. **Create Commitment**
   - Select apps, set limits, lock in

2. **Check Logs**
   ```
   LOCKIN AuthorizationView: deadlineDate from backend: 2025-01-13
   AUTH AuthorizationView: ✅ Using backend deadline: 2025-01-13 12:00:00 -0500 (from 2025-01-13)
   ```

3. **Verify Countdown**
   - Should show next Monday (e.g., "4d 12h 30m 15s")
   - Countdown should match backend deadline

---

## What to Look For in Logs

### ✅ Success Indicators:

1. **Backend Deadline Received**
   ```
   LOCKIN AuthorizationView: deadlineDate from backend: 2025-01-13
   ```

2. **Backend Deadline Used**
   ```
   AUTH AuthorizationView: ✅ Using backend deadline: 2025-01-13 12:00:00 -0500 (from 2025-01-13)
   ```

3. **Deadline Stored**
   ```
   RESET AuthorizationView: 🔒 Storing commitment deadline: 2025-01-13 12:00:00 -0500
   RESET AuthorizationView: ✅ Deadline stored successfully: 2025-01-13 12:00:00 -0500
   ```

### ⚠️ Fallback Indicators:

If parsing fails, you'll see:
```
AUTH AuthorizationView: ⚠️ Fallback to local deadline calculation (failed to parse: [date])
```

This is acceptable if the date format is unexpected, but should be investigated.

---

## Testing Checklist

### Normal Mode:
- [ ] App builds and runs
- [ ] Commitment creation succeeds
- [ ] Logs show: "✅ Using backend deadline"
- [ ] Deadline date matches backend response
- [ ] Countdown shows next Monday
- [ ] Countdown time matches stored deadline

### Testing Mode:
- [ ] Backend deployed with `TESTING_MODE=true`
- [ ] Commitment creation succeeds
- [ ] Logs show: "✅ Using backend deadline"
- [ ] Deadline date is ~3 minutes from now
- [ ] Countdown shows ~3 minutes
- [ ] Countdown time matches stored deadline

### Fallback:
- [ ] Simulate invalid date format (if possible)
- [ ] App doesn't crash
- [ ] Logs show: "⚠️ Fallback to local deadline calculation"
- [ ] Countdown still works (shows next Monday)

---

## Quick Test Commands

### 1. Check Logs in Xcode Console

**Filter by**:
- `"deadline"`
- `"AUTH AuthorizationView"`
- `"Using backend deadline"`

**Expected Output** (Normal Mode):
```
LOCKIN AuthorizationView: deadlineDate from backend: 2025-01-13
AUTH AuthorizationView: ✅ Using backend deadline: 2025-01-13 12:00:00 -0500 (from 2025-01-13)
RESET AuthorizationView: 🔒 Storing commitment deadline: 2025-01-13 12:00:00 -0500
RESET AuthorizationView: ✅ Deadline stored successfully: 2025-01-13 12:00:00 -0500
```

**Expected Output** (Testing Mode):
```
LOCKIN AuthorizationView: deadlineDate from backend: 2025-12-31
AUTH AuthorizationView: ✅ Using backend deadline: 2025-12-31 12:00:00 -0500 (from 2025-12-31)
RESET AuthorizationView: 🔒 Storing commitment deadline: 2025-12-31 12:00:00 -0500
RESET AuthorizationView: ✅ Deadline stored successfully: 2025-12-31 12:00:00 -0500
```

---

## Verification Steps

### Step 1: Check Code Structure

**Verify the code exists**:
```bash
# Check for deadline parsing code
grep -n "deadlineDate" payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/Views/AuthorizationView.swift

# Check for DateFormatter
grep -n "DateFormatter" payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/Views/AuthorizationView.swift

# Check for fallback
grep -n "Fallback" payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/Views/AuthorizationView.swift
```

**Expected**: Should find all three

---

### Step 2: Build iOS App

**In Xcode**:
1. Open `payattentionclub-app-1.1.xcodeproj`
2. Select target: `payattentionclub-app-1.1`
3. Select simulator: iPhone 15 (or any iOS device)
4. Build: Cmd+B
5. Run: Cmd+R

**Or via command line**:
```bash
cd payattentionclub-app-1.1
xcodebuild -project payattentionclub-app-1.1.xcodeproj \
  -scheme payattentionclub-app-1.1 \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

---

### Step 3: Create Commitment and Check Logs

**In iOS App**:
1. Sign in (or use existing session)
2. Navigate to setup screen
3. Select apps to limit
4. Set limit (e.g., 60 minutes)
5. Set penalty (e.g., $0.10/minute)
6. Tap "Lock in" button

**In Xcode Console**:
- Watch for logs starting with "LOCKIN AuthorizationView" or "AUTH AuthorizationView"
- Look for "deadlineDate from backend"
- Look for "✅ Using backend deadline" or "⚠️ Fallback"

---

### Step 4: Verify Countdown Display

**After commitment creation**:
1. Navigate to MonitorView (or wherever countdown is displayed)
2. Check countdown timer

**Normal Mode**:
- Should show: "4d 12h 30m 15s" (example, depends on current time)
- Days should be 1-7 (until next Monday)

**Testing Mode**:
- Should show: "0d 0h 3m 0s" (approximately)
- Minutes should be ~3

---

### Step 5: Verify Deadline Storage

**Add Debug Code** (temporary, for testing):
```swift
// In MonitorView or any view, add:
let storedDeadline = UsageTracker.shared.getCommitmentDeadline()
print("DEBUG: Stored deadline: \(storedDeadline ?? Date())")
```

**Or check via breakpoint**:
1. Set breakpoint after commitment creation
2. In debugger: `po UsageTracker.shared.getCommitmentDeadline()`
3. Verify date matches backend deadline

---

## Troubleshooting

### Issue: "⚠️ Fallback to local deadline calculation"

**Possible Causes**:
1. Backend returned invalid date format
2. Date parsing failed
3. Timezone issue

**Fix**:
- Check backend response format
- Verify `deadlineDate` is in `"yyyy-MM-dd"` format
- Check logs for exact date string received

---

### Issue: Countdown shows wrong time

**Possible Causes**:
1. Deadline not stored correctly
2. Countdown using wrong deadline source
3. Timezone mismatch

**Fix**:
1. Check logs for stored deadline
2. Verify `UsageTracker.shared.getCommitmentDeadline()` returns correct date
3. Check if countdown uses stored deadline or calculates locally

---

### Issue: App crashes on commitment creation

**Possible Causes**:
1. Date parsing error not handled
2. Nil deadline stored
3. Timezone conversion issue

**Fix**:
1. Check crash logs
2. Verify fallback logic is working
3. Check date formatter configuration

---

## Success Criteria

✅ **Step 2.1 is working when**:

1. ✅ Logs show: "✅ Using backend deadline"
2. ✅ Deadline matches backend response
3. ✅ Normal mode: Countdown shows next Monday
4. ✅ Testing mode: Countdown shows ~3 minutes
5. ✅ Deadline is stored correctly
6. ✅ Countdown updates correctly
7. ✅ No crashes
8. ✅ Fallback works if needed

---

## Quick Verification Script

**For Xcode Console** (copy-paste to filter logs):

```
deadline
```

**Or more specific**:
```
AUTH AuthorizationView.*deadline
```

**Expected log sequence**:
1. `LOCKIN AuthorizationView: deadlineDate from backend: [date]`
2. `AUTH AuthorizationView: ✅ Using backend deadline: [date] (from [dateString])`
3. `RESET AuthorizationView: 🔒 Storing commitment deadline: [date]`
4. `RESET AuthorizationView: ✅ Deadline stored successfully: [date]`

---

**End of iOS Testing Guide**


