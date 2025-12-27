# Verification Checklist

## ✅ Pre-Build Checks

- [ ] All files added to correct targets
- [ ] App Group capability enabled for both targets
- [ ] App Group name matches: `group.com.payattentionclub2.0.app`
- [ ] Deployment target is iOS 16.0+
- [ ] DeviceActivityMonitorExtension target exists and is active

## ✅ Build Verification

1. **Clean Build Folder**: Shift+Cmd+K
2. **Build**: Cmd+B
3. Should build without errors ✅

If you get errors:
- Check that all Swift files are added to correct targets
- Verify imports are correct (DeviceActivity, FamilyControls)
- Check that Deployment Target is iOS 16.0+

## ✅ Run on Device

**IMPORTANT**: Screen Time APIs only work on physical devices, not simulator!

1. Connect your iPhone/iPad
2. Select your device as the run destination
3. Run: Cmd+R
4. App should launch ✅

## ✅ Navigation Flow Test

Test the complete flow:

1. **Loading View** → Should appear briefly, then auto-navigate to Setup
2. **Setup View**:
   - Adjust time limit slider → Should update display
   - Adjust penalty slider → Should update display
   - Tap "Select Apps" → FamilyActivityPicker should appear
   - Select some apps
   - Tap "Commit" → Should navigate to ScreenTimeAccess
3. **ScreenTimeAccess View**:
   - Tap "Grant Access" → System authorization dialog appears
   - Grant permission → Should navigate to Authorization
4. **Authorization View**:
   - Should show calculated authorization amount
   - Should show countdown timer
   - Tap "Lock In and Start Monitoring" → Should navigate to Monitor
5. **Monitor View**:
   - Should show countdown timer
   - Should show progress bar (starts at 0)
   - Should show current penalty (starts at $0.00)
   - Progress bar should update every 5 seconds
6. **Bulletin View** (via "Skip to next deadline"):
   - Should show countdown
   - Should show recap
   - Tap "Commit again" → Should navigate back to Setup

## ✅ Monitor Extension Test

1. After "Lock In" is pressed, Monitor Extension should start
2. **Use the selected apps** (actually open and use them)
3. Wait for threshold events (1min, 5min, etc.)
4. Check Console.app for extension logs:
   - Filter by: `DeviceActivityMonitorExtension`
   - Look for: `eventDidReachThreshold` logs
5. Progress bar in MonitorView should update as you use apps

## ✅ App Group Data Sharing Test

1. In MonitorView, progress bar should update every 5 seconds
2. This means:
   - Monitor Extension is writing to App Group ✅
   - Main app is reading from App Group ✅
   - Data is being shared correctly ✅

## 🐛 Common Issues

### Navigation Not Working
- Check that RootRouterView is using @EnvironmentObject
- Verify model.navigate() is being called
- Check Console for any errors

### Monitor Extension Not Firing
- Verify you're on a physical device
- Verify you're actually using the selected apps
- Check that monitoring was started (check logs)
- Verify threshold events are configured (1min, 5min, etc.)

### Progress Bar Not Updating
- Check that UsageTracker is reading from App Group
- Verify Monitor Extension is writing to App Group
- Check Console for any errors
- Verify timer is running (every 5 seconds)

### Build Errors
- Verify all files are in correct targets
- Check imports (DeviceActivity, FamilyControls)
- Verify Deployment Target is iOS 16.0+
- Clean build folder and rebuild

## 📝 Next Steps After Verification

Once everything is working:
1. Test the full user flow end-to-end
2. Verify penalty calculations are correct
3. Test with different time limits and penalties
4. Verify countdown timer accuracy
5. Test navigation between all screens

## 🎉 Success Criteria

You'll know it's working when:
- ✅ All screens navigate correctly
- ✅ Progress bar updates as you use apps
- ✅ Penalty increases when you exceed limit
- ✅ Countdown timer shows correct time to next Monday noon EST
- ✅ App Group data is shared between extension and main app

