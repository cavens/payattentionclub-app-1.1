# Apple OAuth Key for Staging and Production

## Short Answer

**Yes, you can use the same Apple OAuth secret key (.p8 file) for both staging and production environments.**

## Why the Same Key Works

The Apple OAuth secret key is tied to:
- Your **Apple Developer Team ID** (not environment-specific)
- Your **Services ID** (can accept multiple redirect URLs)
- Your **Key ID** (the same key can be used for multiple apps)

The differentiation between staging and production happens at:
- **Supabase project level** (different projects = different redirect URLs)
- **Services ID configuration** (one Services ID can have multiple redirect URLs)

## Configuration

### Option 1: Same Key, Same Services ID (Recommended)

**Use the same key and Services ID for both environments:**

1. **In Apple Developer Portal:**
   - Use one Services ID (e.g., `com.yourcompany.yourapp`)
   - Configure it with **multiple redirect URLs**:
     - Staging: `https://auqujbppoytkeqdsgrbl.supabase.co/auth/v1/callback`
     - Production: `https://whdftvcrtrsnefhprebj.supabase.co/auth/v1/callback`

2. **In Supabase (both projects):**
   - Use the **same**:
     - Services ID
     - Secret Key (.p8 content)
     - Team ID
     - Key ID
   - The only difference is the redirect URL (handled automatically by Supabase)

### Option 2: Same Key, Different Services IDs (Optional)

If you want separate Services IDs for staging/production:

1. **Create two Services IDs:**
   - Staging: `com.yourcompany.yourapp.staging`
   - Production: `com.yourcompany.yourapp`

2. **Use the same key** for both (or create separate keys if preferred)

3. **Configure each Services ID** with its respective redirect URL

## What to Configure in Supabase

### Staging Project
- **Services ID**: `com.yourcompany.yourapp` (or your staging Services ID)
- **Secret Key**: Same .p8 content
- **Team ID**: Same Team ID
- **Key ID**: Same Key ID

### Production Project
- **Services ID**: `com.yourcompany.yourapp` (or your production Services ID)
- **Secret Key**: Same .p8 content
- **Team ID**: Same Team ID
- **Key ID**: Same Key ID

## Services ID Redirect URL Configuration

In Apple Developer Portal, your Services ID should have **both** redirect URLs configured:

1. Go to **Identifiers** → Your Services ID
2. Click **"Configure"** under Sign In with Apple
3. Add **both** return URLs:
   - `https://auqujbppoytkeqdsgrbl.supabase.co/auth/v1/callback` (Staging)
   - `https://whdftvcrtrsnefhprebj.supabase.co/auth/v1/callback` (Production)
4. Click **"Save"**

## Security Considerations

### Using Same Key (Recommended for Most Cases)
✅ **Pros:**
- Simpler to manage
- One key to rotate
- Standard practice for most apps

❌ **Cons:**
- If key is compromised, both environments are affected
- Less isolation between environments

### Using Different Keys (Optional)
✅ **Pros:**
- Better security isolation
- Can rotate keys independently
- Staging issues don't affect production

❌ **Cons:**
- More keys to manage
- More complex setup
- Usually unnecessary for most apps

## Recommendation

**For most apps, use the same key and Services ID for both environments.**

This is the standard approach because:
1. The key is tied to your Apple Developer account, not to specific environments
2. Supabase projects handle the environment separation via different redirect URLs
3. Simpler to manage and rotate
4. Apple's Services ID can accept multiple redirect URLs

## Quick Setup Checklist

- [ ] Create/download Apple OAuth key (.p8 file)
- [ ] Note Key ID, Team ID, and Services ID
- [ ] Configure Services ID with both redirect URLs in Apple Developer
- [ ] Configure Apple provider in **Staging** Supabase project
- [ ] Configure Apple provider in **Production** Supabase project (same values)
- [ ] Test sign-in in both environments

## Troubleshooting

### "Invalid redirect URL" Error

- Make sure both redirect URLs are added to your Services ID in Apple Developer
- URLs must match exactly (case-sensitive)
- Check that the Services ID matches what you entered in Supabase

### "Key not found" Error

- Verify the Key ID matches in both Supabase projects
- Make sure you're using the same key for both environments
- Check that the key hasn't been deleted in Apple Developer

