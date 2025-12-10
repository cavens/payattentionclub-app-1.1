# FamilyActivityPicker Not Showing Apps - Troubleshooting

## Issue
The `FamilyActivityPicker` appears but no apps are shown/selectable.

## Possible Causes

### 1. Authorization Not Granted
**Most Common Issue**: The picker requires FamilyControls authorization to be **approved** before it will show apps.

**Check:**
- Go to **Settings → Screen Time → [Your App]**
- Verify it's **enabled/allowed**

**Fix:**
- The app now requests authorization before showing the picker
- If denied, go to Settings and enable it manually

### 2. Screen Time Not Enabled on Device
**Issue**: Screen Time must be enabled on the device for the picker to work.

**Check:**
- Go to **Settings → Screen Time**
- Verify Screen Time is **ON** (not "Off")

**Fix:**
- Enable Screen Time in Settings
- Set up Screen Time if prompted

### 3. iOS Simulator Limitation
**Issue**: FamilyActivityPicker often doesn't show apps in iOS Simulator.

**Fix:**
- Test on a **physical device** instead

### 4. iOS Version Issue
**Issue**: Some iOS versions have bugs with FamilyActivityPicker.

**Check:**
- What iOS version are you running?
- Is it iOS 16.0+? (Required for DeviceActivity)

### 5. Authorization Status
**Check in Xcode Console:**
When you tap "Select Apps to Limit", look for:
```
SETUP SetupView: Authorization status: X
```

**Status Codes:**
- `0` = `.notDetermined` - Need to request
- `1` = `.denied` - User denied, need to enable in Settings
- `2` = `.approved` - ✅ Should work

---

## Current Code Behavior

The app now:
1. Checks authorization status when "Select Apps" is tapped
2. Requests authorization if not approved
3. Shows picker after authorization is granted (or attempts to show it anyway)

---

## Manual Fix Steps

1. **Delete app** from device
2. **Go to Settings → Screen Time → [Your App]** → Remove if listed
3. **Reinstall app**
4. **Go through onboarding** - grant Screen Time access when prompted
5. **Then try selecting apps**

---

## Alternative: Check Device Settings

1. **Settings → Screen Time**
2. **Make sure Screen Time is ON**
3. **Scroll down** to find your app
4. **Tap on it** → Make sure it's **allowed/enabled**
5. **Return to app** and try selecting apps again

---

## Debug Logs to Check

When tapping "Select Apps to Limit", check Xcode Console for:
- `SETUP SetupView: Authorization status: X`
- `SETUP SetupView: Requesting authorization before showing picker...`
- `SETUP SetupView: Authorization result: X`
- `SETUP SetupView: Picker shown - Authorization status: X`

These will tell you exactly what's happening with authorization.

---

## Known iOS Issues

- Some iOS versions have bugs where picker shows but apps don't appear
- Screen Time must be enabled on device
- Authorization must be approved (not just requested)
- Simulator often doesn't work - use physical device

---

**Last Updated**: 2025-01-XX








