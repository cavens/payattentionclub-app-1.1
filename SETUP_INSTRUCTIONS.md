# Setup Instructions for PayAttentionClub 1.1

## Step 1: Create Xcode Project

1. Open Xcode
2. **File → New → Project**
3. Choose **iOS** → **App**
4. Configure:
   - **Product Name**: `payattentionclub-app-1.1`
   - **Team**: Your team
   - **Organization Identifier**: `com.payattentionclub`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
   - **Minimum Deployment**: iOS 16.0
5. Save to: `/Users/jefcavens/Cursor-projects/payattentionclub-app-1.1/`

## Step 2: Add App Group

1. Select the **main app target**
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Add group: `group.com.payattentionclub.app`
6. ✅ Check the box to enable it

## Step 3: Add DeviceActivityMonitorExtension

1. **File → New → Target**
2. Choose **iOS** → **App Extension** → **Device Activity Monitor Extension**
3. Name: `DeviceActivityMonitorExtension`
4. **IMPORTANT**: When prompted, choose **Activate** to add it to the scheme
5. In the extension target's **Signing & Capabilities**:
   - Add **App Groups** capability
   - Add the same group: `group.com.payattentionclub.app`
   - ✅ Check the box

## Step 4: Add Required Frameworks

For the **main app target**:
- Go to **Target → General → Frameworks, Libraries, and Embedded Content**
- Verify these are present (should be automatic):
  - `DeviceActivity.framework`
  - `FamilyControls.framework`

## Step 5: Copy Files

Copy all Swift files from this directory into your Xcode project:

### Main App Files (add to main app target):
- `payattentionclub_app_1_1App.swift` → Replace the default App file
- `Models/AppModel.swift` → Create Models group, add file
- `Views/LoadingView.swift` → Create Views group, add file
- `Views/SetupView.swift` → Create Views group, add file
- `Views/ScreenTimeAccessView.swift` → Create Views group, add file
- `Views/AuthorizationView.swift` → Create Views group, add file
- `Views/MonitorView.swift` → Create Views group, add file
- `Views/BulletinView.swift` → Create Views group, add file
- `Views/CountdownView.swift` → Create Views group, add file
- `Utilities/UsageTracker.swift` → Create Utilities group, add file
- `Utilities/MonitoringManager.swift` → Create Utilities group, add file

### Monitor Extension Files (add to DeviceActivityMonitorExtension target):
- `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` → Replace the default extension file

## Step 6: Verify Target Membership

For each file, verify it's added to the correct target:

1. Select a file in Xcode
2. Open **File Inspector** (right panel)
3. Under **Target Membership**, check:
   - Main app files → ✅ `payattentionclub-app-1.1`
   - Monitor extension files → ✅ `DeviceActivityMonitorExtension`

## Step 7: Update Info.plist Files

### DeviceActivityMonitorExtension Info.plist
Verify it has:
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.deviceactivity.monitor-extension</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension</string>
</dict>
```

## Step 8: Build and Test

1. **Product → Clean Build Folder** (Shift+Cmd+K)
2. **Product → Build** (Cmd+B)
3. **Product → Run** (Cmd+R) on a **physical device**
   - ⚠️ Screen Time APIs only work on physical devices, not simulator

## Step 9: Test Flow

1. Launch app → Should show LoadingView, then SetupView
2. Set time limit and penalty
3. Select apps to limit
4. Tap "Commit" → Should show ScreenTimeAccessView
5. Tap "Grant Access" → System authorization dialog
6. After authorization → Should show AuthorizationView
7. Tap "Lock In and Start Monitoring" → Should show MonitorView
8. Use the selected apps → Monitor Extension should track usage
9. Progress bar should update every 5 seconds

## Troubleshooting

### App Group Not Working
- Verify all targets have App Groups capability enabled
- Verify group name matches exactly: `group.com.payattentionclub.app`
- Check that UserDefaults(suiteName:) returns non-nil

### Monitor Extension Not Firing
- Verify you're testing on a physical device
- Verify you're actually using the selected apps
- Check Console.app for extension logs
- Verify threshold events are configured (1min, 5min, etc.)

### Navigation Not Working
- Verify RootRouterView is using @EnvironmentObject
- Check that model.navigate() is being called on main thread
- Use navigateAfterYield() after system UI interactions

## Next Steps

After setup is complete:
1. Test the full navigation flow
2. Verify App Group data sharing
3. Test Monitor Extension threshold events
4. Verify progress bar updates

