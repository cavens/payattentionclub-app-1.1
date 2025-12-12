# Enable Apple Sign-In in Supabase

## Problem

Error when trying to sign in:
```
Provider (issuer "https://appleid.apple.com") is not enabled
```

## Solution

Apple Sign-In needs to be enabled in each Supabase project (staging and production).

## Step-by-Step Instructions

### For Staging Environment

1. **Go to Staging Project Dashboard**
   - URL: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl

2. **Navigate to Authentication Settings**
   - In the left sidebar, click **"Authentication"**
   - Click **"Providers"** tab

3. **Enable Apple Provider**
   - Find **"Apple"** in the list of providers
   - Toggle it **ON** (enable it)
   - You'll need to configure:
     - **Services ID**: Your Apple Services ID (from Apple Developer)
     - **Secret Key**: Your Apple Sign-In key (`.p8` file content)
     - **Team ID**: Your Apple Developer Team ID
     - **Key ID**: Your Apple Sign-In Key ID

4. **Get Apple Sign-In Credentials**
   - Go to [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list)
   - Navigate to **Certificates, Identifiers & Profiles**
   - Under **Identifiers**, find your Services ID
   - Under **Keys**, find your Sign In with Apple key

5. **Configure Redirect URLs**
   - In Supabase, go to **Authentication → URL Configuration**
   - Add redirect URL: `https://auqujbppoytkeqdsgrbl.supabase.co/auth/v1/callback`
   - Also add your iOS app's redirect URL if needed

### For Production Environment

1. **Go to Production Project Dashboard**
   - URL: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj

2. **Follow same steps as staging**
   - Navigate to **Authentication → Providers**
   - Enable **Apple** provider
   - Use the same Apple credentials (or create separate ones for production)
   - Configure redirect URL: `https://whdftvcrtrsnefhprebj.supabase.co/auth/v1/callback`

## Apple Sign-In Configuration Details

### Services ID
- Format: `com.yourcompany.yourapp`
- Found in: Apple Developer → Identifiers → Services IDs

### Secret Key (.p8 file)
- Download from: Apple Developer → Keys → Sign In with Apple
- Copy the entire key content (starts with `-----BEGIN PRIVATE KEY-----`)

### Team ID
- Found in: Apple Developer → Membership
- Format: `XXXXXXXXXX` (10 characters)

### Key ID
- Found in: Apple Developer → Keys → Sign In with Apple
- Format: `XXXXXXXXXX` (10 characters)

## Verify Configuration

After enabling:

1. **Check Provider Status**
   - Go to **Authentication → Providers**
   - Apple should show as **Enabled** (green toggle)

2. **Test Sign-In**
   - Try signing in with Apple in your iOS app
   - Should work without the "provider not enabled" error

## Troubleshooting

### Still Getting "Provider Not Enabled"

1. **Check if Apple is enabled**
   - Go to Authentication → Providers
   - Verify Apple toggle is ON

2. **Check Redirect URLs**
   - Make sure the redirect URL matches your Supabase project URL
   - Format: `https://[PROJECT_REF].supabase.co/auth/v1/callback`

3. **Verify Apple Credentials**
   - Double-check Services ID, Team ID, Key ID
   - Verify the secret key is correct (full .p8 content)

### "Invalid Client" Error

- Check that your Services ID matches what's configured in Apple Developer
- Verify the redirect URL is registered in Apple Developer → Services ID → Sign In with Apple

### Different Credentials for Staging/Production

If you want separate Apple Sign-In setups:
- Create separate Services IDs in Apple Developer
- Configure each one in the respective Supabase project
- Use different bundle IDs for staging vs production builds

## Quick Reference

| Setting | Staging | Production |
|---------|---------|------------|
| Project URL | `auqujbppoytkeqdsgrbl.supabase.co` | `whdftvcrtrsnefhprebj.supabase.co` |
| Redirect URL | `https://auqujbppoytkeqdsgrbl.supabase.co/auth/v1/callback` | `https://whdftvcrtrsnefhprebj.supabase.co/auth/v1/callback` |
| Services ID | Same or separate | Same or separate |
| Team ID | Same | Same |
| Key ID | Same or separate | Same or separate |

## Next Steps

After enabling Apple Sign-In:
1. ✅ Test sign-in in staging
2. ✅ Test sign-in in production
3. ✅ Verify user is created in `auth.users` table
4. ✅ Verify user is created in `public.users` table


