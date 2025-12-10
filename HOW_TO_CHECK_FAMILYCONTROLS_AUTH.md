# How to Check FamilyControls Authorization

## Method 1: Check in App (Automatic)

The app automatically checks authorization status. When you tap **"Start Debug Monitoring"**, it will log:
```
DEBUG MonitorView: FamilyControls authorization status: X
```

**Status Values:**
- `0` = `.notDetermined` - User hasn't been asked yet
- `1` = `.denied` - User denied permission
- `2` = `.approved` - ✅ **User granted permission** (this is what you need)

---

## Method 2: Check in iOS Settings

1. Open **Settings** app on your iPhone
2. Go to **Screen Time**
3. Scroll down to find your app name: **"payattentionclub-app-1.1"**
4. Tap on it
5. Check if it says **"Allowed"** or shows a toggle that's **ON**

**If you don't see your app listed:**
- Authorization hasn't been requested yet
- Or it was denied

---

## Method 3: Request Authorization in App

If authorization is not granted:

1. **Go through the app's onboarding flow:**
   - The app should show a `ScreenTimeAccessView` that requests permission
   - Tap **"Request Screen Time Access"**
   - Follow the iOS prompts

2. **Or manually trigger it:**
   - Navigate to the setup/onboarding screens
   - The app will automatically request authorization when needed

---

## Method 4: Check Xcode Console Logs

When the app starts, look for:
```
MARKERS SetupView: Authorization status: approved
```
or
```
MARKERS ScreenTimeAccessView: Authorization status on appear: approved
```

**If you see `notDetermined` or `denied`:**
- You need to grant permission through the app's UI
- Or go to Settings → Screen Time → [Your App] and enable it

---

## Quick Test

1. **Tap "Start Debug Monitoring" button** in MonitorView
2. **Check Xcode Console** for:
   ```
   DEBUG MonitorView: FamilyControls authorization status: 2
   ```
   - If you see `2` = ✅ Approved (good!)
   - If you see `0` or `1` = ❌ Not approved (need to grant permission)

---

## If Authorization is Denied

1. **Go to Settings → Screen Time**
2. **Find your app** in the list
3. **Toggle it ON** or tap **"Allow"**

**Note:** If the app isn't listed, you may need to:
- Delete and reinstall the app
- Go through the app's authorization flow again

---

## Expected Flow

1. App launches → Checks authorization status
2. If `notDetermined` → Shows `ScreenTimeAccessView` → User taps "Request"
3. iOS shows permission dialog → User grants permission
4. Status becomes `approved` → App can use DeviceActivity APIs
5. Extension can be invoked by iOS

---

**Status Code Reference:**
- `0` = `.notDetermined` - Need to request
- `1` = `.denied` - User denied, need to enable in Settings
- `2` = `.approved` - ✅ Ready to use!








