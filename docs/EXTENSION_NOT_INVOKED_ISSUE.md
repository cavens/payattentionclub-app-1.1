# DeviceActivityMonitorExtension Not Being Invoked

## Problem Summary

The `DeviceActivityMonitorExtension` is **not being invoked by iOS**, even though:
- Monitoring starts successfully (`MonitoringManager` logs confirm)
- Extension is properly configured (Info.plist, entitlements, embedded)
- User has created commitments and used limited apps

**Result**: No `daily_usage_*` entries are written to App Group, so `UsageSyncManager` finds 0 entries to sync.

---

## Symptoms

### ✅ What Works
- `MonitoringManager.startMonitoring()` succeeds
- Logs show: `MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring with 140 events`
- App Group is accessible (we can read other keys like `commitmentId`, `baselineTimeSpent`, etc.)
- Extension code is properly configured

### ❌ What Doesn't Work (Updated)
- **Extension logs now appear** ✅ - We see `EXTENSION: 🚀 init` and `EXTENSION: 🔔 eventDidReachThreshold`
- **No `daily_usage_*` keys** in App Group - Extension fails to write because `commitmentId` missing
- **Progress bar regression** - Doesn't show time spent anymore (UI issue)
- Extension callbacks ARE being called, but data writing fails due to missing App Group data

---

## What We've Verified

### 1. Extension Configuration ✅
- **Info.plist**: Correctly configured with `com.apple.deviceactivity.monitor-extension`
- **Entitlements**: Has `com.apple.developer.family-controls`, App Group, and network client
- **Embedded**: Extension is properly embedded in main app target (`Embed Foundation Extensions` build phase)
- **Bundle ID**: `com.payattentionclub.payattentionclub-app-1-1.DeviceActivityMonitorExtension`

### 2. Monitoring Setup ✅
- `MonitoringManager` successfully creates 140 threshold events
- `DeviceActivityCenter.startMonitoring()` succeeds
- User has created commitments and used limited apps

### 3. App Group Access ✅
- Main app can read/write to App Group
- Keys like `commitmentId`, `baselineTimeSpent`, `supabaseAccessToken` exist
- `UsageSyncManager` can access App Group (finds 47-60 total keys, but 0 `daily_usage_*` keys)

---

## Diagnostic Logs Added

We've added extensive logging to help debug:

### Extension Initialization
```swift
override init() {
    super.init()
    NSLog("EXTENSION DeviceActivityMonitorExtension: 🚀🚀🚀 EXTENSION INITIALIZED!")
}
```
**Check for**: `EXTENSION DeviceActivityMonitorExtension: 🚀🚀🚀 EXTENSION INITIALIZED!`
- If seen → Extension is loading
- If not seen → Extension isn't being loaded/embedded properly

### Interval Start Callback
```swift
override func intervalDidStart(for activity: DeviceActivityName) {
    NSLog("EXTENSION DeviceActivityMonitorExtension: 🟢🟢🟢 intervalDidStart for %@", activity.rawValue)
}
```
**Check for**: `EXTENSION DeviceActivityMonitorExtension: 🟢🟢🟢 intervalDidStart`
- If seen → Extension is being called by iOS
- If not seen → iOS isn't invoking the extension

### Threshold Event Callback
```swift
override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    NSLog("EXTENSION DeviceActivityMonitorExtension: 🔔🔔🔔 eventDidReachThreshold called!")
}
```
**Check for**: `EXTENSION DeviceActivityMonitorExtension: 🔔🔔🔔 eventDidReachThreshold called!`
- If seen → Extension is receiving threshold events
- If not seen → Thresholds aren't triggering the extension

---

## Possible Causes

### 1. Extension Not Properly Embedded/Signed
- Extension might not be included in app bundle
- Code signing might be incorrect
- Extension might need to be reinstalled

### 2. iOS Not Invoking Extension
- Extension might need device restart after installation
- iOS might be silently failing to load extension
- Extension might be crashing silently on initialization

### 3. Timing/State Issues
- Extension might only be invoked when app is in specific state
- Extension might need app to be running (unlikely, but possible)
- Extension might need Screen Time permissions to be refreshed

### 4. Configuration Issues
- Extension principal class might not match (`$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension`)
- Bundle identifier mismatch
- Entitlements not properly applied

---

## Next Steps to Debug

### ✅ Step 1: Verify Extension is Loaded - COMPLETE
- Extension IS loading - We see `EXTENSION: 🚀 init` logs ✅

### ✅ Step 2: Verify Extension is Invoked - COMPLETE  
- Extension IS being invoked - We see `EXTENSION: 🔔 eventDidReachThreshold t_XXXs` logs ✅

### 🔄 Step 3: Fix Data Writing (Current Focus)
1. **Create a NEW commitment** - This will store `commitmentId` in App Group
2. Use limited apps for 1-2 minutes
3. **Check Xcode Console** for:
   - `EXTENSION: ✅ Found commitmentId: [UUID]`
   - `EXTENSION: ✅ Found commitmentDeadline: YYYY-MM-DD`
   - `EXTENSION: ✨ Created new daily usage entry...`
   - `EXTENSION: ✅ Stored daily usage entry...`
4. **Check Daily Usage Test View** - Should show entries

### 🔄 Step 4: Fix Progress Bar Regression
1. Investigate `MonitorView.swift` - Check progress bar update logic
2. Check `UsageTracker.swift` - Verify data reading methods
3. Compare with previous working version
4. Test after fixing data writing (Step 3)

### Step 3: Check for Silent Crashes
1. In Xcode: **Window → Devices and Simulators**
2. Select your device
3. Click **"View Device Logs"** (or **"Open Console"**)
4. Look for crash logs containing `DeviceActivityMonitorExtension`
5. Check for any errors during extension initialization

### Step 4: Verify Extension Bundle
1. After installing app, check device logs for extension loading
2. Look for any errors related to extension loading
3. Verify extension is actually embedded in app bundle

### Step 5: Try Device Restart
- Sometimes extensions need device restart to be properly registered
- Restart device after installing app
- Then test again

---

## Files Modified

1. **`DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`**
   - Added `init()` with diagnostic log
   - Added enhanced logging to `intervalDidStart()`
   - Added diagnostic log to `eventDidReachThreshold()`

---

## Related Files

- `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` - Extension implementation
- `DeviceActivityMonitorExtension/Info.plist` - Extension configuration
- `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements` - Extension entitlements
- `Utilities/MonitoringManager.swift` - Starts monitoring (working ✅)
- `Utilities/UsageSyncManager.swift` - Reads daily usage entries (finds 0 entries ❌)
- `Views/DailyUsageTestView.swift` - Test view to verify entries (shows 0 entries ❌)

---

## Current Status

**Status**: 🟡 **PARTIALLY RESOLVED** - Extension IS being invoked, but data writing has issues

**Update (Latest Testing)**:
- ✅ Extension IS being invoked - We see `EXTENSION: 🚀 init` logs
- ✅ Extension IS receiving threshold events - We see `EXTENSION: 🔔 eventDidReachThreshold t_XXXs` logs
- ✅ Extension IS attempting to write data - We see `EXTENSION: 📝 updateDailyUsageEntry called` logs
- ❌ Extension fails to write data - Missing `commitmentId` in App Group (needs new commitment)
- ❌ Progress bar doesn't show time spent anymore (regression)

**Impact**: 
- Extension is working, but data writing fails due to missing App Group data
- Progress bar regression needs investigation
- Phase 2 (Enhanced Local Storage) partially working - needs new commitment to test fully
- Phase 3 (Sync Manager) has nothing to sync until data writing works

**Priority**: 🟡 **MEDIUM** - Extension works, but data flow needs fixing

---

## Notes

- Extension configuration appears correct based on code inspection
- Monitoring starts successfully, so the issue is specifically with extension invocation
- This is a common issue with DeviceActivityMonitorExtension - often requires:
  - Fresh app install
  - Device restart
  - Proper code signing
  - Extension properly embedded

---

## References

- [Apple Documentation: DeviceActivityMonitorExtension](https://developer.apple.com/documentation/deviceactivity)
- [REVISED_EXTENSION_ARCHITECTURE_PLAN.md](./REVISED_EXTENSION_ARCHITECTURE_PLAN.md) - Phase 2 implementation plan
- [KNOWN_ISSUES.md](./KNOWN_ISSUES.md) - Other known issues

---

---

## Latest Diagnostic Attempts

### Added Bundle Verification
Added `verifyExtensionInBundle()` function to `MonitorView` that:
- Checks if extension is in app bundle at `Bundle.main.builtInPlugInsPath`
- Lists all extensions found
- Verifies `DeviceActivityMonitorExtension.appex` exists
- Reads extension's Info.plist to verify configuration

**To check**: Look for logs starting with `EXTENSION DEBUG:` when MonitorView appears.

### Enhanced MonitoringManager Logging
Added detailed schedule logging to help diagnose timing issues.

---

## Critical Next Steps

### 1. Check Bundle Verification Logs
After rebuilding and running, check Xcode Console for:
```
EXTENSION DEBUG: Found X extensions in bundle
EXTENSION DEBUG: Extension names: ...
EXTENSION DEBUG: ✅ DeviceActivityMonitorExtension found: ...
```
- If extension is found → Extension is embedded ✅
- If NOT found → Extension isn't being embedded ❌

### 2. Check for Silent Crashes
If extension is in bundle but no logs appear:
- Extension might be crashing on initialization
- Check device crash logs (Window → Devices → Open Console)
- Look for `DeviceActivityMonitorExtension` crashes

### 3. Verify Principal Class Name
The Info.plist uses `$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension`
- At build time, this should resolve to: `DeviceActivityMonitorExtension.DeviceActivityMonitorExtension`
- Verify this matches the actual class name

### 4. Check if Extension Needs Explicit Registration
Some extensions require explicit registration. Try:
- Restart device after installing app
- Grant Screen Time permissions again
- Create a new commitment after restart

---

## Possible Root Cause

If extension is in bundle but still not invoked, the most likely causes are:

1. **Extension crashing on init** - Check crash logs
2. **Principal class name mismatch** - Verify `$(PRODUCT_MODULE_NAME)` resolves correctly
3. **iOS lazy loading** - Extension only loads when actually needed (threshold hit)
4. **Code signing issue** - Extension not properly signed

---

---

## Latest Update (2025-01-XX)

### ✅ Extension IS Being Invoked!

**Confirmed Working**:
- Extension initialization: `EXTENSION: 🚀 init` ✅
- Threshold events: `EXTENSION: 🔔 eventDidReachThreshold t_180s` ✅
- Extension attempting data write: `EXTENSION: 📝 updateDailyUsageEntry called` ✅

**Current Issue**: Data writing fails because:
- `commitmentId` not found in App Group (commitment created before `storeCommitmentId()` was added)
- `commitmentDeadline` stored as timestamp, now correctly read
- **Solution**: Create a NEW commitment to store `commitmentId` in App Group

### ❌ New Issue: Progress Bar Regression

**Problem**: Progress bar doesn't show time spent anymore

**Symptoms**:
- Daily usage test screen shows time spent correctly
- Progress bar in MonitorView does NOT show time spent
- This is a regression from previous behavior

**Possible Causes**:
- Data reading logic changed
- Progress bar update logic broken
- App Group data not being read correctly by MonitorView

**Files to Check**:
- `Views/MonitorView.swift` - Progress bar implementation
- `Utilities/UsageTracker.swift` - Data reading methods
- App Group data structure changes

**Priority**: 🟡 **MEDIUM** - UI regression, doesn't block core functionality

---

**Last Updated**: 2025-01-XX
**Assigned To**: TBD
**Status**: 🟡 Partially Resolved - Extension works, data writing needs new commitment, progress bar needs fix

