# Phase 3 Testing Guide - iOS Configuration

## ✅ Automated Verification

Run the verification script:
```bash
./scripts/verify_ios_config.sh
```

This checks that:
- Staging URL is correct
- Production URL is correct
- Environment switching logic is in place

---

## 📱 Manual Testing in Xcode

### Test 1: Debug Build (Should Use Staging)

1. **Open Xcode**
   - Open `payattentionclub-app-1.1.xcodeproj`

2. **Select Debug Configuration**
   - Ensure build configuration is set to "Debug"
   - Check: Product → Scheme → Edit Scheme → Run → Build Configuration = "Debug"

3. **Build and Run**
   - Press `⌘R` or click the Play button
   - Run on a simulator or device

4. **Open Dev Menu**
   - Navigate to the CountdownView (main screen with timer)
   - **Triple-tap** on the countdown logo/timer
   - Dev Menu should appear

5. **Verify Configuration**
   - Check "Environment" row → Should show **"STAGING"**
   - Check "Supabase URL" row → Should show **`https://auqujbppoytkeqdsgrbl.supabase.co`**
   - Check "Stripe Mode" row → Should show **"test"**

6. **Test Connection**
   - Try signing in with Apple
   - Verify the app connects to staging database
   - Check staging Supabase dashboard to see if user appears

**Expected Result:**
- ✅ Environment: STAGING
- ✅ Supabase URL: `https://auqujbppoytkeqdsgrbl.supabase.co`
- ✅ Stripe Mode: test
- ✅ Can sign in and data appears in staging

---

### Test 2: Release Build (Should Use Production)

1. **Change Build Configuration**
   - Product → Scheme → Edit Scheme
   - Select "Run" in left sidebar
   - Change "Build Configuration" from "Debug" to "Release"
   - Click "Close"

2. **Build and Run**
   - Press `⌘R` or click the Play button
   - ⚠️ **Note:** Release builds may have optimizations that affect debugging

3. **Open Dev Menu**
   - Navigate to CountdownView
   - **Triple-tap** on the countdown logo

4. **Verify Configuration**
   - Check "Environment" row → Should show **"Production"**
   - Check "Supabase URL" row → Should show **`https://whdftvcrtrsnefhprebj.supabase.co`**
   - Check "Stripe Mode" row → Should show **"production"**

**Expected Result:**
- ✅ Environment: Production
- ✅ Supabase URL: `https://whdftvcrtrsnefhprebj.supabase.co`
- ✅ Stripe Mode: production

---

### Test 3: Archive Build (Production)

1. **Create Archive**
   - Product → Archive
   - Wait for build to complete

2. **Verify in Archive**
   - The archived build should use production configuration
   - This is what will be submitted to App Store

**Expected Result:**
- ✅ Archive uses production environment
- ✅ Ready for App Store submission

---

## 🔍 Troubleshooting

### Dev Menu Not Appearing
- Make sure you're on the CountdownView (main timer screen)
- Try triple-tapping directly on the timer/countdown display
- Check that you're in a Debug build (Dev Menu only appears in Debug)

### Wrong Environment Showing
- Check build configuration: Product → Scheme → Edit Scheme → Run
- Verify Config.swift has correct URLs
- Clean build folder: Product → Clean Build Folder (⇧⌘K)
- Rebuild: Product → Build (⌘B)

### Can't Connect to Staging
- Verify staging Supabase project is running
- Check network connection
- Verify staging anon key is correct in Config.swift
- Check Supabase dashboard for any errors

### Can't Connect to Production
- Verify production Supabase project is running
- Check network connection
- Verify production anon key is correct in Config.swift
- Check Supabase dashboard for any errors

---

## ✅ Success Criteria

Phase 3 is successfully tested when:

1. ✅ Debug builds show "STAGING" environment
2. ✅ Debug builds connect to staging Supabase (`auqujbppoytkeqdsgrbl`)
3. ✅ Release builds show "Production" environment
4. ✅ Release builds connect to production Supabase (`whdftvcrtrsnefhprebj`)
5. ✅ Dev Menu displays correct environment and URLs
6. ✅ App can sign in and interact with the correct database

---

## 📝 Notes

- **Dev Menu** is only available in Debug builds
- **Environment switching** is automatic based on build configuration
- **Manual override** is available via `AppConfig.overrideEnvironment` if needed
- **Staging** is safe for testing - won't affect production data
- **Production** should only be used for final testing before release

