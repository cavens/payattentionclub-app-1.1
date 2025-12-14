# Frontend (iOS) Deployment Flow

This document explains the complete flow for deploying the iOS app to production.

---

## Overview

**Key Point:** Frontend deployment is **separate** from backend deployment. You can deploy them independently.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Local Git  │     │   Xcode    │     │ App Store  │
│  (main)     │ --> │  Archive   │ --> │  Connect   │
└─────────────┘     └─────────────┘     └─────────────┘
     │                    │                    │
     │                    │                    │
     │ 1. Code in git     │                    │
     │ 2. Build RELEASE   │                    │
     │    (production)    │                    │
     │                    │ 3. Upload .ipa     │
     │                    │                    │
     │                    │                    │ 4. Submit
     │                    │                    │    for review
```

---

## Step-by-Step: Frontend Deployment

### Step 1: Code is Ready in `main` Branch

```bash
git checkout main
git status
# Shows: All changes committed and pushed
```

**What's in `main`:**
- Updated Swift files
- Updated UI/UX
- All changes tested on staging
- Backend compatibility verified

---

### Step 2: Run Tests (Optional but Recommended)

```bash
# Run iOS unit tests in Xcode
# Product → Test (⌘U)

# Or run from command line
xcodebuild test -scheme payattentionclub-app-1.1 -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Why:** Catch bugs before building for production.

---

### Step 3: Build Archive in Xcode

1. **Open Xcode**
2. **Select RELEASE scheme** (not DEBUG)
   - Scheme: `payattentionclub-app-1.1`
   - Configuration: Release
3. **Product → Archive**
   - Xcode builds optimized binary
   - Creates `.xcarchive` file
   - **RELEASE mode = connects to production backend**

**What happens:**
- Xcode compiles Swift code
- Links with production Supabase URLs (from `Config.swift`)
- Creates optimized binary (smaller, faster)
- Signs with your distribution certificate

---

### Step 4: Distribute Archive

1. **Xcode Organizer opens** (shows your archive)
2. **Click "Distribute App"**
3. **Choose distribution method:**
   - **App Store Connect** (for App Store release)
   - **TestFlight** (for beta testing)
   - **Ad Hoc** (for specific devices)
4. **Follow prompts:**
   - Select distribution certificate
   - Upload symbols (for crash reports)
   - Upload to App Store Connect

**What happens:**
- Xcode creates `.ipa` file (iOS app package)
- Uploads to App Store Connect via API
- Processing takes 10-30 minutes

---

### Step 5: Submit for Review (App Store Connect)

1. **Go to App Store Connect** (web UI)
   - https://appstoreconnect.apple.com
2. **Select your app**
3. **Go to: App Store → Versions**
4. **Select the new version** (uploaded from Xcode)
5. **Fill in:**
   - Version number
   - What's new in this version
   - Screenshots (if needed)
   - App Store description
6. **Submit for Review**

**What happens:**
- Apple reviews your app (1-3 days typically)
- You get notified of approval/rejection
- Once approved, app goes live on App Store

---

## Complete Frontend Deployment Flow

### Scenario: Releasing Version 1.2.0

**Monday-Wednesday: Development**
```bash
git checkout develop
git checkout -b feat/new-feature
# Edit Swift files
# Test in Xcode (DEBUG = staging)
git commit -m "feat: new feature"
git checkout develop && git merge feat/new-feature
```

**Thursday: Testing**
```bash
# Test on staging
# Run unit tests
# Test production frontend with staging backend
./scripts/test_production_frontend_with_staging.sh
```

**Friday: Production Release**
```bash
# 1. Merge to main
git checkout main
git merge develop
git push origin main

# 2. Build Archive in Xcode
#    Product → Archive (RELEASE mode)

# 3. Distribute App
#    Upload to App Store Connect

# 4. Submit for Review
#    In App Store Connect web UI
```

**Next Week:**
- Apple reviews app
- App goes live on App Store
- Users can download/update

---

## Frontend vs Backend Deployment

| Aspect | Frontend (iOS) | Backend (Supabase) |
|--------|----------------|-------------------|
| **Deployment Method** | Xcode Archive → App Store Connect | Shell script → Supabase API |
| **Time to Deploy** | Minutes (build + upload) | Seconds (API call) |
| **Time to Live** | 1-3 days (Apple review) | Immediate (after deploy) |
| **Can Deploy Separately?** | Yes | Yes |
| **Rollback** | Submit new version | Deploy previous SQL |

**Key Point:** Frontend and backend can be deployed independently. You don't need to deploy both at the same time.

---

## Testing Before Production

### Before Building Archive

1. **Run unit tests**
   ```bash
   # In Xcode: Product → Test (⌘U)
   ```

2. **Test on staging**
   - Build in DEBUG mode
   - Test all critical flows
   - Verify backend compatibility

3. **Test production frontend with staging backend**
   ```bash
   ./scripts/test_production_frontend_with_staging.sh
   ```

### After Building Archive

1. **TestFlight Beta** (Recommended)
   - Distribute to TestFlight
   - Install on your device
   - Test production build before App Store release

2. **Verify production backend compatibility**
   - Ensure backend is deployed
   - Test critical flows with production backend

---

## Version Management

### Version Numbers

**iOS Version** (in `Info.plist`):
```xml
<key>CFBundleShortVersionString</key>
<string>1.2.0</string>
```

**Backend Version** (in `_internal_config` table):
```sql
INSERT INTO _internal_config (key, value) 
VALUES ('backend_version', '1.2.0');
```

**Keep them aligned:**
- Frontend 1.2.0 → Backend 1.2.0
- Makes it easier to track compatibility

---

## Important Notes

### ⚠️ RELEASE Mode = Production Backend

When you build Archive:
- Xcode uses RELEASE configuration
- `Config.swift` selects `.production` environment
- App connects to production Supabase
- **Make sure production backend is deployed first!**

### ⚠️ TestFlight vs App Store

**TestFlight:**
- Faster deployment (minutes)
- Limited to testers
- Good for beta testing
- Doesn't require App Store review

**App Store:**
- Requires Apple review (1-3 days)
- Available to all users
- Production release

### ⚠️ Rollback

**If app has critical bug:**
- Submit new version immediately
- Apple fast-track review (if critical)
- Or use TestFlight for quick fix

**Can't instantly rollback** like backend - need to submit new version.

---

## Summary

**Frontend Deployment = 4 Steps:**

1. **Code in git** (main branch)
2. **Build Archive** (Xcode → Product → Archive)
3. **Distribute** (Upload to App Store Connect)
4. **Submit** (App Store Connect web UI)

**Key Point:** Frontend deployment is manual and separate from backend. Takes 1-3 days due to Apple review.

