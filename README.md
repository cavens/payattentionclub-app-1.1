# PayAttentionClub 1.1

iOS app that helps users limit screen time with monetary penalties and shared accountability pools.

## Project Structure

```
payattentionclub-app-1.1/
├── payattentionclub-app-1.1/          # iOS app source
│   ├── Models/                         # AppModel, CountdownModel, DailyUsageEntry
│   ├── Views/                          # SwiftUI views (Setup, Monitor, Bulletin, etc.)
│   ├── Utilities/                      # BackendClient, UsageTracker, MonitoringManager, etc.
│   └── DeviceActivityMonitorExtension/ # Screen Time monitoring extension
├── supabase/                           # Backend (Supabase)
│   ├── remote_rpcs/                    # SQL RPC functions
│   ├── functions/                      # Edge Functions (TypeScript)
│   ├── migrations/                     # Database migrations
│   └── tests/                          # Backend test suite
├── scripts/                             # Deployment & utility scripts
├── docs/                               # Detailed documentation
├── DEPLOYMENT_WORKFLOW.md              # Complete deployment guide
├── TESTING_GUIDE.md                    # Frontend-to-backend integration testing
├── SECURITY_PLAN.md                    # Security implementation plan (may not be fully implemented)
└── .env                                # Environment variables (gitignored)
```

## Quick Setup

1. **iOS Project**: See `docs/SETUP_INSTRUCTIONS.md` for Xcode project setup
2. **Backend**: Supabase projects configured (staging/production)
3. **Environment**: DEBUG = staging, RELEASE = production (auto-selected in `Config.swift`)
4. **Environment Variables**: Create `.env` file in project root with required variables (see below)

## Environment Variables (.env)

The `.env` file (gitignored) contains all sensitive credentials. Required variables:

### Staging
- `STAGING_SUPABASE_URL`
- `STAGING_SUPABASE_ANON_KEY`
- `STAGING_SUPABASE_SERVICE_ROLE_KEY`
- `STAGING_STRIPE_SECRET_KEY`
- `STAGING_STRIPE_WEBHOOK_SECRET`

### Production
- `PRODUCTION_SUPABASE_URL`
- `PRODUCTION_SUPABASE_ANON_KEY`
- `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY`
- `PRODUCTION_STRIPE_SECRET_KEY`
- `PRODUCTION_STRIPE_WEBHOOK_SECRET`

**Note**: Never commit `.env` to git. Git hooks automatically check for secrets before commit/push.

## Testing

### Backend Tests
```bash
./supabase/tests/run_backend_tests.sh staging
```

### iOS Tests
- **Unit Tests**: Xcode → Product → Test (⌘U)
- **Manual Testing**: See `TESTING_GUIDE.md` for frontend-to-backend integration testing
- **Device Required**: Screen Time APIs only work on physical devices (not simulator)

### Production Compatibility Test
```bash
./scripts/test_production_frontend_with_staging.sh
```

## Deployment

**See `DEPLOYMENT_WORKFLOW.md` for complete workflow.**

Quick reference:
- **Staging**: `./scripts/deploy_to_staging.sh`
- **Production**: `./scripts/deploy_to_production.sh`
- **Frontend**: Xcode → Archive → App Store Connect

## Key Documentation

- `DEPLOYMENT_WORKFLOW.md` - Complete deployment process
- `docs/ARCHITECTURE.md` - System architecture & technical specs
- `docs/SETUP_INSTRUCTIONS.md` - Xcode project setup
- `TESTING_GUIDE.md` - Frontend-to-backend integration testing guide
- `SECURITY_PLAN.md` - Security implementation plan (⚠️ **Note**: May not be fully implemented - review status before assuming features are in place)

## Important Notes

- **App Group**: `group.com.payattentionclub2.0.app` (required for extension ↔ app communication)
- **Git Hooks**: Auto-check secrets and run tests on commit
- **Secrets**: Never commit secrets; use `.env` (gitignored)
- **Environments**: Staging (`auqujbppoytkeqdsgrbl`) / Production (`whdftvcrtrsnefhprebj`)
- **Security**: See `SECURITY_PLAN.md` for planned security measures (implementation status may vary)

## Key Learnings from 1.0

- **RootRouterView pattern**: Use a View (not Scene body) to observe model changes
- **Scene phase gating**: Defer navigation until app is `.active`
- **Monitor Extension → App Group → Main App**: Only data flow that works
- **DeviceActivityReport is sandboxed**: Cannot share data, view-only
