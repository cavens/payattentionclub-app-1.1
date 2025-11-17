# How to Test App Usage Tracking

## Current Status ✅

Everything is working! The app is:
- ✅ Running with new code
- ✅ Monitoring started successfully
- ✅ Waiting for you to use the selected apps

## Next Step: Use the Selected Apps

The Monitor Extension will only fire threshold events when you **actually use** the apps you selected in Setup.

### Steps:

1. **Leave the app** (go to home screen or switch to another app)

2. **Open one of the apps you selected** in Setup (e.g., Safari, Messages, etc.)

3. **Use it continuously for at least 1 minute** (the 1min threshold should fire)

4. **Check Console.app** (NOT Xcode console):
   - Open **Console.app** on your Mac
   - Connect your device via USB
   - Select your device in the left sidebar
   - In the search box, type: `MARKERS MonitorExtension`
   - Press Enter

5. **You should see**:
   ```
   MARKERS MonitorExtension: 🟢 intervalDidStart for PayAttentionClub.Monitoring
   MARKERS MonitorExtension: ⚠️⚠️⚠️ THRESHOLD REACHED!
   MARKERS MonitorExtension: Event: 1min
   MARKERS MonitorExtension: ✅ Stored in App Group: consumedMinutes=1.0
   ```

6. **Go back to the app** (Monitor screen)

7. **Wait 5 seconds** - the timer should update and show usage!

---

## Why Console.app?

**Monitor Extension logs don't appear in Xcode console** - they only appear in Console.app because:
- Extensions run in a separate process
- Xcode only shows logs from the main app process
- Console.app shows logs from ALL processes (including extensions)

---

## What to Look For

### In Console.app (Monitor Extension):
- `MARKERS MonitorExtension: 🟢 intervalDidStart` - Monitoring started
- `MARKERS MonitorExtension: ⚠️⚠️⚠️ THRESHOLD REACHED!` - You used an app for 1+ minutes!
- `MARKERS MonitorExtension: ✅ Stored in App Group` - Data written successfully

### In Xcode Console (Main App):
- `MARKERS UsageTracker: ✅ Real usage detected` - App detected threshold events
- `MARKERS MonitorView: 🔄 updateUsage() - usage: 60 seconds` - Usage updated!

---

## Troubleshooting

### No Monitor Extension logs in Console.app?
- **Make sure you're using the selected apps** (not just opening them briefly)
- **Use continuously for 1+ minutes** (not just opening and closing)
- **Check device is connected** via USB
- **Filter correctly**: `MARKERS MonitorExtension` (exact match)

### Still no logs after using apps?
- **Verify apps were selected** in Setup screen
- **Check MonitoringManager logs**: Should show "Selected apps count: 2" (or more)
- **Try a different app** (some apps might not trigger events immediately)

---

## Success Criteria

✅ Monitor Extension logs appear in Console.app when you use apps  
✅ MonitorView shows actual usage (not 0) after threshold events  
✅ Progress bar reflects real app usage  

---

## Ready? Go use those apps! 🎯




