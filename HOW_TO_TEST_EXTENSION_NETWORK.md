# How to Test DeviceActivityMonitorExtension Network Access

## Overview
We've added a network test (Step 0) that automatically runs when monitoring starts. This test checks if the extension can make HTTP requests.

## When the Test Runs
The network test runs automatically when `intervalDidStart()` is called, which happens when:
1. You create a commitment and start monitoring
2. A new monitoring interval begins

## How to View Test Results

### Option 1: Xcode Console (Easiest)
1. **Connect your iPhone/iPad to your Mac**
2. **Open Xcode**
3. **Run the app on your device** (not simulator - extensions don't work in simulator)
4. **Go to:** Window → Devices and Simulators (Shift+Cmd+2)
5. **Select your device** from the left sidebar
6. **Click "Open Console"** button (or View → Device Logs)
7. **Filter logs:**
   - In the search box, type: `EXTENSION NetworkTest`
   - Or filter by process: `DeviceActivityMonitorExtension`

### Option 2: Console.app (More Detailed)
1. **Open Console.app** on your Mac (Applications → Utilities → Console)
2. **Connect your iPhone/iPad** via USB
3. **Select your device** from the left sidebar
4. **In the search box**, type: `EXTENSION NetworkTest`
5. **Start monitoring** in the app (create a commitment and lock in)
6. **Watch for log messages** starting with `EXTENSION NetworkTest:`

### Option 3: Xcode Debug Console (During Development)
1. **Run the app from Xcode** on your device
2. **In Xcode's bottom console**, you should see logs
3. **Look for messages** starting with `EXTENSION NetworkTest:`

## What to Look For

### ✅ Success (Network Access Works)
You should see logs like:
```
EXTENSION NetworkTest: 🧪 Starting network access test...
EXTENSION NetworkTest: 📤 Attempting GET request to https://httpbin.org/get...
EXTENSION NetworkTest: ✅ SUCCESS! Status: 200
EXTENSION NetworkTest: ✅ Network access is WORKING - extension CAN make HTTP requests
EXTENSION NetworkTest: 🧪 Testing POST request (simulating backend call)...
EXTENSION NetworkTest: ✅ POST request SUCCESS! Status: 200
EXTENSION NetworkTest: ✅ Extension CAN make POST requests with JSON body
EXTENSION NetworkTest: 🏁 Network test complete. Check logs above for results.
```

**If you see this:** ✅ Proceed with full network reporting implementation (Steps 1-8)

### ❌ Failure (Network Access Blocked)
You should see logs like:
```
EXTENSION NetworkTest: 🧪 Starting network access test...
EXTENSION NetworkTest: 📤 Attempting GET request to https://httpbin.org/get...
EXTENSION NetworkTest: ❌ FAILED - Network request error: [error description]
EXTENSION NetworkTest: ❌ This extension CANNOT make network calls (or network is unavailable)
EXTENSION NetworkTest: ❌ URLError code: [code], domain: [domain]
```

**If you see this:** ❌ Use Fallback Plan (update `weekly-close` to estimate missing usage)

## Step-by-Step Testing Process

1. **Build and run the app** on a physical device (not simulator)
2. **Sign in** with Apple
3. **Set up Screen Time access** (if not already done)
4. **Create a commitment:**
   - Set a limit (e.g., 30 minutes)
   - Set a penalty (e.g., $0.10/min)
   - Select apps to monitor
   - Click "Lock in the money"
5. **Monitoring starts** → This triggers `intervalDidStart()` → Network test runs
6. **Check logs** using one of the methods above

## Troubleshooting

### No Logs Appearing?
- **Make sure you're testing on a physical device** (extensions don't work in simulator)
- **Check that monitoring actually started** - you should see other extension logs like `MARKERS MonitorExtension: 🟢 intervalDidStart`
- **Try filtering for all extension logs:** Search for `EXTENSION` or `MonitorExtension`

### Test Not Running?
- **Check if monitoring is active:** Look for `MARKERS MonitorExtension: 🟢 intervalDidStart` logs
- **Try force-quitting and reopening the app** to trigger a new interval
- **Check that the extension target is included in the build**

### Network Test Fails But You Have Internet?
- **Check device internet connection** - try opening Safari
- **Check if httpbin.org is accessible** - try opening https://httpbin.org/get in Safari
- **Check entitlements:** Make sure `com.apple.security.network.client` is in `DeviceActivityMonitorExtension.entitlements`

## Expected Behavior

- **Test runs automatically** when monitoring starts
- **No user interaction needed** - it happens in the background
- **Test takes ~2-5 seconds** to complete
- **Results are logged** to system console (not visible in app UI)

## Next Steps Based on Results

### If Network Access Works ✅
Proceed with implementing full network reporting:
- Step 1: Add commitment ID storage
- Step 2: Store commitment ID when created
- Step 3: Store auth token in App Group
- Step 4: Create ExtensionBackendClient
- Step 5-8: Complete implementation

### If Network Access is Blocked ❌
Use Fallback Plan:
- Update `weekly-close` Edge Function to estimate usage for commitments with missing `daily_usage` records
- This ensures weekly settlements can proceed even without usage data
- See `EXTENSION_NETWORK_REPORTING_PLAN.md` for details

## Notes

- Extension logs go to **system console**, not the app's debug console
- You need to use **Console.app** or **Xcode Device Logs** to see them
- The extension runs in a **separate process** from the main app
- Logs are prefixed with `EXTENSION NetworkTest:` for easy filtering

