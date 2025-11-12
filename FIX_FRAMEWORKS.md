# Fixing Framework Linking

## What You're Seeing

Seeing `DeviceActivityMonitorExtension.appex` in "Frameworks, Libraries, and Embedded Content" is **CORRECT** - that's the extension that needs to be embedded.

The frameworks (`DeviceActivity.framework` and `FamilyControls.framework`) are typically linked automatically when you import them in code, but let's verify and add them explicitly if needed.

## Step 1: Verify Frameworks Are Imported in Code

Check that your main app files have these imports:

- `payattentionclub_app_1_1App.swift` should have:
  ```swift
  import DeviceActivity
  import FamilyControls
  ```

- `Models/AppModel.swift` should have:
  ```swift
  import FamilyControls
  import DeviceActivity
  ```

- `Views/SetupView.swift` should have:
  ```swift
  import FamilyControls
  ```

- `Views/ScreenTimeAccessView.swift` should have:
  ```swift
  import FamilyControls
  ```

- `Views/AuthorizationView.swift` should have:
  ```swift
  import DeviceActivity
  import FamilyControls
  ```

- `Utilities/MonitoringManager.swift` should have:
  ```swift
  import DeviceActivity
  import FamilyControls
  ```

## Step 2: Explicitly Add Frameworks (If Needed)

If the frameworks aren't automatically linked, add them manually:

1. Select your **main app target** (payattentionclub-app-1.1)
2. Go to **Build Phases** tab
3. Expand **Link Binary With Libraries**
4. Click the **+** button
5. Search for and add:
   - `DeviceActivity.framework`
   - `FamilyControls.framework`
6. Make sure both are set to **"Do Not Embed"** (they're system frameworks)

## Step 3: Verify Build Settings

1. Select your **main app target**
2. Go to **Build Settings** tab
3. Search for "Other Linker Flags"
4. Verify it's not blocking the frameworks

## Step 4: Check for Build Errors

Try building the project (Cmd+B). If you see errors like:
- "No such module 'DeviceActivity'"
- "No such module 'FamilyControls'"

Then you need to:
1. Make sure your **Deployment Target** is iOS 16.0 or higher
2. Clean Build Folder (Shift+Cmd+K)
3. Delete Derived Data
4. Rebuild

## What Should Be in "Frameworks, Libraries, and Embedded Content"

For the **main app target**, you should see:
- ✅ `DeviceActivityMonitorExtension.appex` (set to "Embed & Sign" or "Embed Without Signing")
- ✅ `DeviceActivity.framework` (if explicitly added, set to "Do Not Embed")
- ✅ `FamilyControls.framework` (if explicitly added, set to "Do Not Embed")

**Note**: In modern Xcode, system frameworks are often linked automatically and may not appear in this list. The important thing is that your code compiles without errors.

## Quick Test

1. Open `payattentionclub_app_1_1App.swift`
2. Try building (Cmd+B)
3. If it builds successfully, the frameworks are linked correctly
4. If you get "No such module" errors, follow Step 2 above

## For the Extension Target

The **DeviceActivityMonitorExtension** target should automatically have:
- `DeviceActivity.framework` linked (it's required for the extension)

You don't need to manually add frameworks to the extension target - Xcode handles this automatically when you create a Device Activity Monitor Extension.

