# Navigation After Payment Confirmation - Analysis

**Date**: 2026-01-15  
**Issue**: Payment is confirmed but app doesn't navigate to monitor screen

---

## Problem

After payment is confirmed in Test 3 (Create Commitment - Normal Mode), the app doesn't navigate to the monitor screen.

---

## Code Flow Analysis

### Current Flow in `lockInAndStartMonitoring()`

1. **Step 1**: Check billing status ✅
2. **Step 1.5**: Handle PaymentIntent (if needed) ✅
   - Payment confirmed
   - `savedPaymentMethodId` set
3. **Step 2**: Create commitment ✅
   - Commitment created successfully
4. **Step 3**: Store baseline time ✅
5. **Step 4**: Store deadline ✅
6. **Step 5**: Prepare thresholds (if needed) ✅
7. **Step 6**: Clear loading state ✅
8. **Step 7**: Set `isStartingMonitoring = true` ✅
9. **Step 8**: Navigate to monitor ❌ **PROBLEM HERE**
10. **Step 9**: Start monitoring in background

---

## Issues Identified

### Issue 1: `navigateAfterYield()` Doesn't Await Task

**Location**: Line 379-381 in `AuthorizationView.swift`

```swift
await MainActor.run {
    model.navigateAfterYield(.monitor)
}
```

**Problem**: `navigateAfterYield()` creates a `Task` but doesn't return it or await it:

```swift
func navigateAfterYield(_ screen: AppScreen) {
    Task { @MainActor in
        await Task.yield() // Let the runloop present/dismiss system UI
        navigate(screen)
    }
}
```

**Impact**: The `Task` is created but not awaited, so:
- The function returns immediately
- Navigation might happen later (or not at all if the view is dismissed)
- The calling code continues without waiting for navigation

**Why it might work sometimes**: If the Task runs quickly enough, navigation happens. But if there's any delay or the view is dismissed, navigation might not occur.

---

### Issue 2: Missing Task Wrapper for Background Monitoring

**Location**: Line 388-400 in `AuthorizationView.swift`

**Current Code**:
```swift
if #available(iOS 16.0, *) {
    
    await MonitoringManager.shared.startMonitoring(
        selection: model.selectedApps,
        limitMinutes: Int(model.limitMinutes)
    )
    
    // Clear loading state after monitoring starts
    await MainActor.run {
        model.isStartingMonitoring = false
    }
}
```

**Problem**: The comment says "Start monitoring in background", but `startMonitoring()` is being awaited directly. This means:
- Navigation happens (line 380)
- Then code waits for monitoring to start (line 390)
- If `startMonitoring()` takes time or fails, it could block or throw an error
- If an error is thrown, it would be caught by the outer `catch` block (line 407), preventing navigation

**Expected Code** (based on comment):
```swift
if #available(iOS 16.0, *) {
    Task {  // Missing Task wrapper!
        await MonitoringManager.shared.startMonitoring(
            selection: model.selectedApps,
            limitMinutes: Int(model.limitMinutes)
        )
        
        // Clear loading state after monitoring starts
        await MainActor.run {
            model.isStartingMonitoring = false
        }
    }
}
```

---

### Issue 3: Error Handling Could Swallow Navigation

**Location**: Line 407-415 in `AuthorizationView.swift`

```swift
} catch {
    NSLog("LOCKIN AuthorizationView: ❌ Error during lock in: \(error.localizedDescription)")
    await MainActor.run {
        isLockingIn = false
        lockInError = "Failed to lock in: \(error.localizedDescription)"
    }
}
```

**Problem**: If any error occurs after payment confirmation but before navigation completes, the error is caught and navigation is prevented. However, the user said payment is confirmed, so the error must be happening after that.

**Possible scenarios**:
1. `prepareThresholds()` throws an error (line 361-364)
2. `startMonitoring()` throws an error (line 390) - but this should be in a Task
3. Deadline parsing fails (line 274-330) - but this has fallback logic
4. Some other async operation fails

---

### Issue 4: Navigation Happens Before Monitoring Starts

**Location**: Line 378-384 in `AuthorizationView.swift`

**Current Flow**:
1. Navigate to monitor (line 380)
2. Wait 0.3 seconds (line 384)
3. Start monitoring (line 390)

**Problem**: If `startMonitoring()` throws an error, it happens after navigation. But if the error is caught, it might prevent the navigation from completing or cause the view to be dismissed.

---

## Root Cause Hypothesis

**Most Likely**: Issue 2 - Missing Task wrapper for `startMonitoring()`

**Why**:
1. Payment is confirmed ✅
2. Commitment is created ✅
3. Navigation is called ✅
4. But then `startMonitoring()` is awaited directly (not in a Task)
5. If `startMonitoring()` takes time or throws an error, it could:
   - Block the navigation from completing
   - Throw an error that prevents navigation
   - Cause the view to be dismissed before navigation completes

**Evidence**:
- The comment says "Start monitoring in background" but it's not actually in a background Task
- The code structure suggests a Task wrapper was intended (based on the comment)
- If monitoring fails, it would throw an error that prevents navigation

---

## Recommendations

### Fix 1: Make `navigateAfterYield()` Awaitable

**Change**:
```swift
func navigateAfterYield(_ screen: AppScreen) async {
    await Task.yield() // Let the runloop present/dismiss system UI
    await MainActor.run {
        navigate(screen)
    }
}
```

**Then call it**:
```swift
await model.navigateAfterYield(.monitor)
```

**Benefit**: Ensures navigation completes before continuing.

---

### Fix 2: Wrap `startMonitoring()` in a Task

**Change**:
```swift
// Start monitoring in background (after navigation and delay)
if #available(iOS 16.0, *) {
    Task {  // Add Task wrapper
        await MonitoringManager.shared.startMonitoring(
            selection: model.selectedApps,
            limitMinutes: Int(model.limitMinutes)
        )
        
        // Clear loading state after monitoring starts
        await MainActor.run {
            model.isStartingMonitoring = false
        }
    }
}
```

**Benefit**: Monitoring runs in background without blocking navigation.

---

### Fix 3: Add Error Handling for Monitoring

**Change**:
```swift
Task {
    do {
        await MonitoringManager.shared.startMonitoring(
            selection: model.selectedApps,
            limitMinutes: Int(model.limitMinutes)
        )
        
        await MainActor.run {
            model.isStartingMonitoring = false
        }
    } catch {
        NSLog("LOCKIN AuthorizationView: ⚠️ Monitoring start failed: \(error.localizedDescription)")
        // Don't prevent navigation if monitoring fails
        await MainActor.run {
            model.isStartingMonitoring = false
        }
    }
}
```

**Benefit**: Monitoring failures don't prevent navigation.

---

### Fix 4: Add Logging to Debug

**Add logs**:
```swift
NSLog("LOCKIN AuthorizationView: Step 8 - About to navigate to monitor...")
await MainActor.run {
    model.navigateAfterYield(.monitor)
}
NSLog("LOCKIN AuthorizationView: Step 8 - Navigation called (may complete later)")

// Small delay to let UI settle after navigation
try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
NSLog("LOCKIN AuthorizationView: Step 9 - Starting monitoring in background...")
```

**Benefit**: Helps identify where the flow stops.

---

## Testing Strategy

1. **Add logging** to see where the flow stops
2. **Check Xcode console** for:
   - "Step 8 - About to navigate to monitor..."
   - "Step 8 - Navigation called..."
   - "Step 9 - Starting monitoring..."
   - Any errors after payment confirmation
3. **Check if navigation Task completes**:
   - Add log inside `navigateAfterYield()` Task
   - Verify it's called
4. **Check for errors**:
   - Look for any errors in the catch block
   - Check if `startMonitoring()` throws an error

---

## Conclusion

**Most Likely Issue**: Missing Task wrapper for `startMonitoring()` causes it to block or throw an error, preventing navigation from completing.

**Recommended Fix**: 
1. Wrap `startMonitoring()` in a Task (Fix 2)
2. Add error handling for monitoring (Fix 3)
3. Add logging to debug (Fix 4)
4. Consider making `navigateAfterYield()` awaitable (Fix 1) for better reliability

**Priority**: High - This prevents users from reaching the monitor screen after payment.



