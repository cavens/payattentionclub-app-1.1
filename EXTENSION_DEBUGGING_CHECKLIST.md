# DeviceActivityMonitorExtension Debugging Checklist

## Quick Diagnostic Steps

### Step 1: Verify Extension is Built and Embedded ✅

**In Xcode:**
1. Select the main app target (`payattentionclub-app-1.1`)
2. Go to **Build Phases** tab
3. Expand **"Embed Foundation Extensions"**
4. Verify `DeviceActivityMonitorExtension.appex` is listed ✅

**If missing:**
- The extension won't be included in the app bundle
- Add it manually: Click "+" → Select `DeviceActivityMonitorExtension.appex`

---

### Step 2: Verify Extension Bundle ID ✅

**Check in Xcode:**
1. Select `DeviceActivityMonitorExtension` target
2. Go to **General** tab
3. Verify **Bundle Identifier**: `com.payattentionclub.payattentionclub-app-1-1.DeviceActivityMonitorExtension`

**Check Info.plist:**
- Verify `NSExtensionPrincipalClass` is: `$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension`

---

### Step 3: Clean Build and Fresh Install 🔄

**Critical Steps:**
1. **Delete app completely** from device (long press → Remove App)
2. **Clean build folder**: Cmd+Shift+K
3. **Clean derived data**: Xcode → Preferences → Locations → Click arrow next to Derived Data → Delete folder
4. **Rebuild**: Cmd+B
5. **Install fresh**: Run on device (Cmd+R)
6. **Restart device** (sometimes required for extensions)

---

### Step 4: Check Diagnostic Logs 📊

**After fresh install, check Xcode Console for:**

#### A. Extension Initialization
```
EXTENSION DeviceActivityMonitorExtension: 🚀🚀🚀 EXTENSION INITIALIZED!
```
- ✅ **If seen**: Extension is loading
- ❌ **If NOT seen**: Extension isn't being loaded/embedded properly

#### B. Interval Start (when monitoring begins)
```
EXTENSION DeviceActivityMonitorExtension: 🟢🟢🟢 intervalDidStart for PayAttentionClub.Monitoring
```
- ✅ **If seen**: Extension is being invoked by iOS
- ❌ **If NOT seen**: iOS isn't invoking the extension

**Note**: `intervalDidStart` is called when:
- The monitoring interval actually starts (based on schedule)
- Schedule is: 00:00 to 23:59 daily
- If current time is within this window, interval should start immediately
- If outside window, interval starts at next 00:00

#### C. Threshold Events (when using limited apps)
```
EXTENSION DeviceActivityMonitorExtension: 🔔🔔🔔 eventDidReachThreshold called!
MARKERS MonitorExtension: 🔔 Threshold: t_60s (60 seconds = 1.0 minutes)
```
- ✅ **If seen**: Extension is receiving threshold events
- ❌ **If NOT seen**: Thresholds aren't triggering (or extension not invoked)

---

### Step 5: Verify Monitoring is Active ✅

**Check logs for:**
```
MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring with 140 events
```

**Then:**
1. Create a commitment
2. Use a limited app (e.g., Safari) for 1-2 minutes
3. Check for threshold logs

---

### Step 6: Check for Silent Crashes 🔍

**In Xcode:**
1. **Window → Devices and Simulators**
2. Select your device
3. Click **"Open Console"** (or right-click device → "Open Console")
4. Look for crash logs containing:
   - `DeviceActivityMonitorExtension`
   - `com.payattentionclub.payattentionclub-app-1-1.DeviceActivityMonitorExtension`
5. Check for any errors during extension loading

**Alternative: Terminal**
```bash
# Stream device logs
log stream --device "Your iPhone" --predicate 'process == "DeviceActivityMonitorExtension" OR eventMessage CONTAINS "DeviceActivityMonitorExtension"'
```

---

### Step 7: Verify Schedule Timing ⏰

**Current Schedule:**
- Start: 00:00 (midnight)
- End: 23:59 (11:59 PM)
- Repeats: Daily

**Issue**: If you start monitoring at, say, 2:00 PM, the interval should start immediately since we're within the window.

**Test**: Start monitoring and immediately check for `intervalDidStart` logs. If you don't see them within 10-30 seconds, the extension isn't being invoked.

---

### Step 8: Check Extension Entitlements 🔐

**Verify `DeviceActivityMonitorExtension.entitlements` contains:**
- ✅ `com.apple.developer.family-controls` = `true`
- ✅ `com.apple.security.application-groups` = `["group.com.payattentionclub.app"]`
- ✅ `com.apple.security.network.client` = `true` (if needed)

**Verify main app entitlements also have:**
- ✅ `com.apple.developer.family-controls` = `true`
- ✅ `com.apple.security.application-groups` = `["group.com.payattentionclub.app"]`

---

### Step 9: Test Extension Loading Manually 🧪

**Add this test code to main app (temporary):**

```swift
// In MonitorView or AppModel, after startMonitoring succeeds:
Task {
    // Give iOS a moment to load extension
    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    
    // Check if extension has written anything to App Group
    if let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let extensionKeys = allKeys.filter { $0.hasPrefix("monitorIntervalStart_") }
        NSLog("TEST: Extension keys found: \(extensionKeys.count)")
        if extensionKeys.isEmpty {
            NSLog("TEST: ⚠️ Extension hasn't written anything - might not be invoked")
        }
    }
}
```

---

## Common Issues and Solutions

### Issue 1: Extension Not Embedded
**Symptom**: No extension logs at all, not even `init()`
**Solution**: Verify Step 1 above, manually add extension to "Embed Foundation Extensions"

### Issue 2: Extension Crashes on Init
**Symptom**: Extension logs appear briefly then stop, or crash logs in device console
**Solution**: Check crash logs, verify all dependencies are available to extension

### Issue 3: iOS Not Invoking Extension
**Symptom**: Extension `init()` logs appear, but no `intervalDidStart` logs
**Solution**: 
- Verify schedule is correct
- Restart device
- Reinstall app
- Check if Screen Time permissions are properly granted

### Issue 4: Thresholds Not Triggering
**Symptom**: `intervalDidStart` logs appear, but no `eventDidReachThreshold` logs
**Solution**:
- Verify you're actually using limited apps
- Check that apps are in the selection
- Wait longer (thresholds fire at 1 min, 2 min, 5 min, etc.)

---

## Expected Log Sequence

**When monitoring starts successfully:**
1. `MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring with 140 events`
2. `EXTENSION DeviceActivityMonitorExtension: 🚀🚀🚀 EXTENSION INITIALIZED!` (within seconds)
3. `EXTENSION DeviceActivityMonitorExtension: 🟢🟢🟢 intervalDidStart for PayAttentionClub.Monitoring` (within seconds)
4. `EXTENSION DeviceActivityMonitorExtension: 🔔🔔🔔 eventDidReachThreshold called!` (when using limited apps)

**If you see 1 but not 2-4**: Extension isn't being loaded/invoked
**If you see 1-2 but not 3-4**: Extension is loaded but not being invoked
**If you see 1-3 but not 4**: Extension is working, but thresholds aren't firing

---

## Next Actions Based on Results

### If NO extension logs at all:
1. Verify extension is embedded (Step 1)
2. Clean build and reinstall (Step 3)
3. Check for crash logs (Step 6)

### If `init()` logs but no `intervalDidStart`:
1. Check schedule timing (Step 7)
2. Restart device
3. Verify Screen Time permissions

### If `intervalDidStart` but no threshold logs:
1. Verify you're using limited apps
2. Wait longer (thresholds fire at specific intervals)
3. Check that apps are actually in the selection

---

**Last Updated**: 2025-01-XX
**Status**: 🔴 Debugging in progress



