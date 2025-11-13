# How to See MARKERS Logs

## Option 1: Xcode Debug Console (Easiest)

1. Run the app from Xcode (Cmd+R)
2. In Xcode, look at the **Debug Console** (bottom panel)
3. Filter by typing: `MARKERS`
4. You should see all logs with "MARKERS" prefix

## Option 2: Console.app on Mac (More Reliable)

1. Open **Console.app** on your Mac (Applications → Utilities → Console)
2. Connect your iPhone/iPad via USB
3. In Console.app:
   - Select your device from the left sidebar
   - In the search box (top right), type: `MARKERS`
   - Press Enter
4. You should see all logs with "MARKERS" prefix

## Option 3: Terminal (Command Line)

1. Open Terminal
2. Run:
   ```bash
   log stream --predicate 'process == "payattentionclub-app-1.1" OR process == "DeviceActivityMonitorExtension"' --level debug | grep MARKERS
   ```
3. This will stream logs in real-time

## What Logs to Look For

### When App Starts:
- `MARKERS AppModel: init() called`
- `MARKERS RootRouterView: body accessed`

### When Navigating:
- `MARKERS AppModel: navigate() called`
- `MARKERS RootRouterView: body accessed` (should appear for each screen change)

### In MonitorView (every 5 seconds):
- `MARKERS MonitorView: 🔄 updateUsage()`
- `MARKERS UsageTracker: 📊 Reading App Group data:`
- `MARKERS UsageTracker: ⚠️ No threshold events fired yet` (if no usage)

### When Using Apps (Monitor Extension):
- `MARKERS MonitorExtension: 🟢 intervalDidStart`
- `MARKERS MonitorExtension: ⚠️⚠️⚠️ THRESHOLD REACHED!` (when you use apps for 1+ minutes)

## Troubleshooting

### If you see NO logs at all:

1. **Verify new code is running**:
   - Clean Build Folder (Shift+Cmd+K)
   - Delete Derived Data
   - Rebuild (Cmd+B)
   - Reinstall on device

2. **Check log level**:
   - In Console.app, make sure log level is set to show all messages
   - Try filtering by process name instead: `payattentionclub-app-1.1`

3. **Verify device is connected**:
   - In Console.app, your device should appear in the left sidebar
   - Make sure it's selected

4. **Check Xcode console**:
   - Sometimes logs only appear in Xcode's debug console
   - Make sure the console is visible (View → Debug Area → Show Debug Area)

### If logs appear but no MARKERS:

- The new code might not be running
- Try a clean rebuild and reinstall
- Check that you copied the updated files to Xcode

## Quick Test

Add this to `payattentionclub_app_1_1App.swift` in the `init()`:

```swift
init() {
    NSLog("MARKERS TEST: App init() called")
    print("MARKERS TEST: App init() called")
    fflush(stdout)
}
```

If you see this log, logging is working. If not, there's a build/deployment issue.



