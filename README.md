# PayAttentionClub 1.1

## Architecture Briefing

See `ARCHITECTURE.md` for complete technical specifications.

## Quick Start

1. Follow `SETUP_INSTRUCTIONS.md` to create the Xcode project
2. Copy the Swift files from this directory into your Xcode project
3. Ensure all targets are configured correctly (App Groups, capabilities)
4. Build and test on a physical device

## Key Learnings from 1.0

- **RootRouterView pattern**: Use a View (not Scene body) to observe model changes
- **Scene phase gating**: Defer navigation until app is `.active`
- **Monitor Extension → App Group → Main App**: Only data flow that works
- **DeviceActivityReport is sandboxed**: Cannot share data, view-only

## Project Structure

```
payattentionclub-app-1.1/
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
├── Utilities/
│   ├── UsageTracker.swift
│   └── MonitoringManager.swift
├── DeviceActivityMonitorExtension/
│   └── DeviceActivityMonitorExtension.swift
└── payattentionclub_app_1_1App.swift (main app entry)
```

