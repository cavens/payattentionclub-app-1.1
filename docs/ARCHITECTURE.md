# PayAttentionClub 1.1 - Architecture Briefing

This is the complete technical specification for PayAttentionClub 1.1.

## Mission

PayAttentionClub helps people use their phones less — and stay accountable.

Users set a daily screen-time limit, commit a monetary penalty for exceeding it, and join a weekly shared pool that funds real anti-screen-time campaigns.

## Technical Overview

### Core Stack
- iOS 16.0+
- SwiftUI + Combine
- DeviceActivity + FamilyControls
- App Group: `group.com.payattentionclub2.0.app`
- Extensions:
  - DeviceActivityMonitorExtension (data bridge)
  - DeviceActivityReportExtension (view-only, sandboxed)

### Data-Flow Constraints

**CRITICAL**: Apple's DeviceActivityReport cannot share data outside its sandbox.

| Component | Purpose | Data Sharing | Notes |
|-----------|---------|--------------|-------|
| Main App | UI, limit config, payments | ✅ via App Group | Cannot query live screen time directly |
| Monitor Extension | Threshold callbacks | ✅ via App Group | Writes numeric usage data to App Group |
| Report Extension | Charts view | ❌ sandboxed | Use only for Apple's built-in charts |

**➡️ All numeric screen-time values visible in the main app must come from the Monitor Extension using threshold events or scheduled updates.**

## App Architecture

### AppModel (ObservableObject, @MainActor)
```swift
@Published var currentScreen: AppScreen
@Published var limitMinutes: Double
@Published var penaltyPerMinute: Double
@Published var selectedApps: FamilyActivitySelection
@Published var baselineUsageSeconds: Int
@Published var currentUsageSeconds: Int
@Published var currentPenalty: Double
```

### Navigation Flow
```
Loading → Setup → ScreenTimeAccess → Authorization → Monitor → Bulletin
```

RootRouterView switches on `AppModel.currentScreen` to show the appropriate view.

## Functional Flow

### 1. Loading View
- Placeholder text/logo: "Pay Attention Club"
- Shown at app launch until AppModel initializes

### 2. Setup View
- **Countdown**: (DD : HH : MM : SS) to next Monday 12:00 EST
- **Limit scale**: Slider 30 min → 42 h (21 h midpoint)
- **Penalty scale**: Slider $0.01 → $5 per minute ($0.10 midpoint)
- **App selector**: FamilyActivityPicker
- **Button**: "Commit" → ScreenTimeAccessView

### 3. Screen-Time Access View
- Trigger FamilyControls authorization popup
- Once granted → `AppModel.navigate(.authorization)`

### 4. Authorization View
- **Countdown**: Same Monday 12:00 EST counter
- **Authorization formula**:
  ```
  base = max(5, min(1000,
    (remainingHours - limitHours) * factor1
    + penaltyPerMin * factor2
    + selectedApps.count * factor3
  ))
  ```
- **Button**: "Lock in the money" → stores baseline usage and proceeds to MonitorView

On button press:
1. Retrieve total usage for selected apps (via DeviceActivityMonitor snapshot)
2. Save as `baselineUsageSeconds`
3. Proceed to `.monitor`

### 5. Monitor View
- **Countdown**: Monday 12:00 EST
- **Progress bar**: 0 → user limit (minutes)
- **Time source**: `(currentUsageSeconds - baselineUsageSeconds)` refreshed every ≈ 5 s
- **Penalty**: `(excessMinutes * penaltyPerMinute)`
- **Button**: Temporary "Skip to next deadline" → BulletinView

**Implementation notes**:
- Use DeviceActivityMonitor to post incremental usage events every few minutes
- Store updates to App Group (`currentUsageSeconds`)
- Main app reads and interpolates between thresholds for smooth bar animation

### 6. Bulletin View
- **Countdown**: Monday 12:00 EST
- **Recap**: Total usage + penalty summary for the week
- **Button**: "Commit again" → SetupView

## Data Persistence

All stored in `UserDefaults(suiteName: "group.com.payattentionclub2.0.app")`:

| Key | Description | Writer | Reader |
|-----|-------------|--------|--------|
| `limitMinutes` | User-set time limit | Main app | All |
| `penaltyPerMinute` | User-set penalty | Main app | All |
| `selectedApps` | Tokens of tracked apps | Main app | All |
| `baselineUsageSeconds` | Snapshot at lock-in | AuthorizationView | Monitor |
| `currentUsageSeconds` | Updated from monitor extension | Monitor ext | Main app |
| `currentPenalty` | Derived at runtime | Main app | — |

## Update Cycle (Monitor Extension → Main App)

1. DeviceActivityMonitor fires threshold events (`eventDidReachThreshold`)
2. Extension writes updated `currentUsageSeconds` to App Group
3. Main app observes App Group every few seconds (timer or Combine publisher)
4. UI updates:
   - progress bar width = `(currentUsageSeconds - baseline) / limit`
   - penalty = `max(0, (usage - limit) * penaltyPerMinute)`

## Non-functional Notes

- DeviceActivityReport is view-only — no data transfer out
- All `@Published` changes in AppModel occur on `@MainActor`
- Use `.scenePhase` to defer navigation until app is `.active` (prevents lost updates when Screen Time authorization dialogs appear)
- Avoid blocking main runloop after setting `currentScreen`
- **RootRouterView pattern**: Use a View (not Scene body) to observe model changes - Scene bodies don't re-evaluate

## Testing Checklist

- ✅ Verify FamilyControls authorization flow completes
- ✅ Confirm baseline usage snapshot is stored at "Lock in"
- ✅ Ensure progress bar updates every ≈ 5 s from App Group values
- ✅ Validate penalty math
- ✅ Confirm navigation loop: Setup → Access → Auth → Monitor → Bulletin → Setup
- ✅ Confirm all screen logs fire (RootRouterView.body logging enabled during dev)

## Summary

**Goal**: A minimal, privacy-compliant, fully SwiftUI app that visualizes and gamifies reduced screen time.

**Core rule**: Never try to read numeric data from DeviceActivityReport; all real-time numbers must flow through DeviceActivityMonitor → App Group → Main App.

