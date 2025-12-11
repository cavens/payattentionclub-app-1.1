# Quick Setup - Step 5: Adding Files to Xcode

## Option 1: Use the Script (Easiest)

1. Open Terminal
2. Navigate to the project directory:
   ```bash
   cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
   ```
3. Run the script:
   ```bash
   ./copy_files_to_xcode.sh
   ```
4. Follow the instructions the script prints

## Option 2: Manual Drag & Drop (Also Easy)

### For Main App Files:

1. Open your Xcode project
2. In **Project Navigator** (left sidebar), right-click on the `payattentionclub-app-1.1` folder (the blue one)
3. Select **"Add Files to payattentionclub-app-1.1..."**
4. Navigate to: `/Users/jefcavens/Cursor-projects/payattentionclub-app-1.1/`
5. Select these **folders** (not individual files):
   - `Models`
   - `Views`
   - `Utilities`
6. In the dialog:
   - ✅ Check **"Create groups"** (not "Create folder references")
   - ✅ Check **"Add to targets: payattentionclub-app-1.1"**
   - ❌ Uncheck **"Copy items if needed"** (files are already in the right place)
7. Click **"Add"**

### For the Main App File:

1. In Project Navigator, find `payattentionclub_app_1_1App.swift` (the default one)
2. Delete it (Move to Trash)
3. Right-click on `payattentionclub-app-1.1` folder
4. Select **"Add Files to payattentionclub-app-1.1..."**
5. Navigate to: `/Users/jefcavens/Cursor-projects/payattentionclub-app-1.1/`
6. Select: `payattentionclub_app_1_1App.swift`
7. Check **"Add to targets: payattentionclub-app-1.1"**
8. Click **"Add"**

### For Monitor Extension:

1. In Project Navigator, find `DeviceActivityMonitorExtension` folder
2. Find the default `DeviceActivityMonitorExtension.swift` file
3. Delete it (Move to Trash)
4. Right-click on `DeviceActivityMonitorExtension` folder
5. Select **"Add Files to DeviceActivityMonitorExtension..."**
6. Navigate to: `/Users/jefcavens/Cursor-projects/payattentionclub-app-1.1/DeviceActivityMonitorExtension/`
7. Select: `DeviceActivityMonitorExtension.swift`
8. Check **"Add to targets: DeviceActivityMonitorExtension"**
9. Click **"Add"**

## Verify Everything is Added

After adding files, verify in Project Navigator you see:

```
payattentionclub-app-1.1/
├── payattentionclub_app_1_1App.swift
├── Models/
│   └── AppModel.swift
├── Views/
│   ├── LoadingView.swift
│   ├── SetupView.swift
│   ├── ScreenTimeAccessView.swift
│   ├── AuthorizationView.swift
│   ├── MonitorView.swift
│   ├── BulletinView.swift
│   └── CountdownView.swift
└── Utilities/
    ├── UsageTracker.swift
    └── MonitoringManager.swift

DeviceActivityMonitorExtension/
└── DeviceActivityMonitorExtension.swift
```

## Quick Check: Build the Project

1. Press **Cmd+B** to build
2. If it builds successfully, you're done! ✅
3. If you get errors about missing files, double-check target membership (Step 6)

