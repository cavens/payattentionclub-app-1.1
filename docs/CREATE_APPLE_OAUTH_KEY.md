# How to Create Apple Sign-In Secret Key (.p8)

## Overview

Apple Sign-In requires a private key (.p8 file) that you generate in the Apple Developer portal. This key is used to create JWT tokens for authentication.

## Step-by-Step Instructions

### Step 1: Access Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Sign in with your Apple Developer account
3. Navigate to **Certificates, Identifiers & Profiles**

### Step 2: Create a Key

1. In the left sidebar, click **"Keys"**
2. Click the **"+"** button (top left) to create a new key
3. Fill in the form:
   - **Key Name**: Give it a descriptive name (e.g., "Sign In with Apple - PayAttentionClub")
   - **Enable "Sign In with Apple"**: ✅ Check this box
4. Click **"Continue"**
5. Review and click **"Register"**

### Step 3: Download the Key

⚠️ **IMPORTANT: You can only download the key ONCE!**

1. After creating the key, you'll see a download button
2. Click **"Download"** to download the `.p8` file
3. **Save it securely** - you cannot download it again!
4. Note down the **Key ID** shown on the page (you'll need this)

### Step 4: Get Your Team ID

1. In Apple Developer Portal, go to **Membership**
2. Your **Team ID** is displayed at the top (10-character string)
3. Copy this - you'll need it for Supabase configuration

### Step 5: Get Your Services ID

1. Go to **Identifiers** in the left sidebar
2. Find your **Services ID** (or create one if you don't have it)
3. Click on it to view details
4. Under **"Sign In with Apple"**, click **"Configure"**
5. Set up:
   - **Primary App ID**: Select your app's bundle ID
   - **Website URLs**:
     - **Domains**: `supabase.co`
     - **Return URLs**: 
       - Staging: `https://auqujbppoytkeqdsgrbl.supabase.co/auth/v1/callback`
       - Production: `https://whdftvcrtrsnefhprebj.supabase.co/auth/v1/callback`
6. Click **"Save"** and then **"Continue"** and **"Register"**

### Step 6: Configure in Supabase

1. **Open the .p8 file** you downloaded
   - It should look like:
     ```
     -----BEGIN PRIVATE KEY-----
     MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg...
     -----END PRIVATE KEY-----
     ```

2. **Copy the ENTIRE content** (including BEGIN/END lines)

3. **Go to Supabase Dashboard**
   - Staging: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/auth/providers
   - Production: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/providers

4. **Enable Apple Provider**
   - Toggle Apple to **ON**
   - Fill in the form:
     - **Services ID**: Your Services ID (e.g., `com.yourcompany.yourapp`)
     - **Secret Key**: Paste the ENTIRE .p8 file content
     - **Team ID**: Your Team ID (from Step 4)
     - **Key ID**: The Key ID (from Step 3)

5. **Click "Save"**

## What You Need to Collect

Before configuring in Supabase, gather:

| Item | Where to Find | Example |
|------|---------------|---------|
| **Services ID** | Identifiers → Services IDs | `com.yourcompany.yourapp` |
| **Secret Key** | Keys → Download .p8 file | Entire .p8 file content |
| **Team ID** | Membership page | `ABC123DEF4` |
| **Key ID** | Keys → Your key | `XYZ789GHI0` |

## Troubleshooting

### "Key file not found" or "Can't download key"

- ⚠️ You can only download the .p8 key **once** when you create it
- If you lost it, you need to:
  1. Create a new key in Apple Developer
  2. Update your Services ID to use the new key
  3. Update Supabase with the new key

### "Invalid key format"

- Make sure you're copying the **entire** .p8 file content
- Include the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines
- Don't modify the key content

### "Services ID not found"

- Make sure your Services ID is registered in Apple Developer
- Check that "Sign In with Apple" is enabled for that Services ID
- Verify the Services ID matches what you're entering in Supabase

### "Invalid redirect URL"

- Make sure the redirect URLs in Apple Developer match exactly:
  - Staging: `https://auqujbppoytkeqdsgrbl.supabase.co/auth/v1/callback`
  - Production: `https://whdftvcrtrsnefhprebj.supabase.co/auth/v1/callback`
- URLs are case-sensitive and must match exactly

## Security Best Practices

1. **Store .p8 file securely**
   - Never commit it to git
   - Store in password manager or secure file storage
   - Add to `.gitignore` if storing locally

2. **Use separate keys for staging/production** (optional)
   - You can use the same key for both, or create separate keys
   - Separate keys provide better security isolation

3. **Rotate keys periodically**
   - Create new keys every 6-12 months
   - Update Supabase when rotating

## Quick Reference Links

- **Apple Developer Portal**: https://developer.apple.com/account
- **Keys**: https://developer.apple.com/account/resources/authkeys/list
- **Identifiers**: https://developer.apple.com/account/resources/identifiers/list
- **Membership**: https://developer.apple.com/account/#/membership

## Example .p8 File Content

```
-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg...
(many lines of base64 encoded data)
...
-----END PRIVATE KEY-----
```

Copy this **entire block** into Supabase's "Secret Key" field.

