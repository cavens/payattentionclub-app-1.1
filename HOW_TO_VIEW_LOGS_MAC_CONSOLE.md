# How to View Logs in Mac Console

## Method 1: Mac Console App (for Physical Device)

1. **Connect your iPhone/iPad** via USB
2. **Open Console app** (Applications → Utilities → Console)
3. **Select your device** in the sidebar (under "Devices")
4. **In the search bar**, type: `sync` or `SYNC` or `com.payattentionclub.payattentionclub-app-1-1`
5. **Filter by subsystem**: Look for `com.payattentionclub.payattentionclub-app-1-1`
6. **Filter by category**: Look for `sync` category
7. **Or filter by process**: Look for `payattentionclub-app-1-1`

**Troubleshooting if logs don't appear:**
- Make sure device is **unlocked** and **trusted**
- Try filtering by process name: `payattentionclub-app-1.1`
- Check Action menu → Include Info Messages (to show .info level logs)
- Try Action menu → Include Debug Messages (to show .debug level logs)
- Restart Console app if needed

**Note**: Mac Console typically only shows logs from **physical devices**, not simulators.

---

## Method 2: Terminal `log stream` (Works for Simulator)

### For iOS Simulator:
```bash
# Stream all logs from simulator
log stream --predicate 'process == "payattentionclub-app-1.1"'

# Or filter by subsystem (use actual bundle ID)
log stream --predicate 'subsystem == "com.payattentionclub.payattentionclub-app-1-1" AND category == "sync"'

# Or search for SYNC keyword
log stream --predicate 'eventMessage CONTAINS "SYNC"'
```

### For Physical Device:
```bash
# First, get device name
xcrun xctrace list devices

# Then stream from device (replace "Your iPhone" with actual device name)
log stream --device "Your iPhone" --predicate 'subsystem == "com.payattentionclub.payattentionclub-app-1-1" AND category == "sync"'
```

---

## Method 3: Xcode Console (Current Method - Working)

This is what you're currently using and it works! The logs appear in:
- **Xcode → Debug Area → Console** (bottom panel)
- Filter by typing "SYNC" in the search box

---

## Why Mac Console Might Not Show Simulator Logs

Mac Console app is primarily designed for:
- **Physical devices** connected via USB
- **System logs** from macOS itself
- **App logs** from Mac apps

iOS Simulator logs are better viewed via:
- **Xcode Console** (what you're using now) ✅
- **Terminal `log stream`** command (Method 2 above)

---

## Quick Test: Verify os_log is Working

Run this in Terminal while your app is running:

```bash
log stream --predicate 'subsystem == "com.payattentionclub.payattentionclub-app-1-1" AND category == "sync"'
```

You should see logs streaming in real-time. If you see them here but not in Mac Console app, that's normal - Mac Console doesn't show simulator logs well.

---

## Recommendation

**For development**: Use **Xcode Console** (what you're doing now) - it's the most reliable.

**For production debugging on physical devices**: Use **Mac Console app** or **Terminal log stream**.

