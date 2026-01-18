# How to Create a Personal Access Token (PAT) in Supabase

## Step-by-Step Instructions

### Method 1: Via Dashboard (Most Common)

1. **Log in to Supabase Dashboard**
   - Go to: https://supabase.com/dashboard
   - Make sure you're logged in

2. **Click your Profile Icon**
   - Look for your profile picture/avatar in the **top-right corner** of the dashboard
   - Click on it

3. **Navigate to Account Settings**
   - In the dropdown menu, look for one of these options:
     - **"Account Preferences"** (most common)
     - **"Account Settings"**
     - **"Settings"**
     - **"Profile"**
   - Click on it

4. **Find Access Tokens Section**
   - In the account settings page, look for:
     - **"Access Tokens"** tab or section
     - **"Personal Access Tokens"**
     - **"API Tokens"**
   - This is usually in a sidebar or as a tab

5. **Generate New Token**
   - Click **"Generate New Token"** or **"Create Token"** button
   - Give it a name (e.g., "Edge Function Secret Updater")
   - Click **"Generate"** or **"Create"**

6. **Copy the Token Immediately**
   - ⚠️ **IMPORTANT**: The token is only shown once!
   - Copy it immediately
   - Store it securely (you'll need it for the next step)

### Method 2: Direct URL (If Available)

Try these URLs directly (may vary based on your account):

- https://supabase.com/dashboard/account/tokens
- https://supabase.com/dashboard/account/access-tokens
- https://supabase.com/dashboard/account/preferences
- https://app.supabase.com/account/tokens

### Method 3: Via Supabase CLI

If you have the Supabase CLI installed, you can also generate tokens via CLI:

```bash
# Login to Supabase
supabase login

# This will open a browser and guide you through token creation
```

## If You Can't Find It

### Possible Reasons:

1. **UI Changed**: Supabase occasionally updates their dashboard layout
   - **Solution**: Look for "Settings" or "Account" in the profile dropdown

2. **Organization Account**: If you're part of an organization, PATs might be managed differently
   - **Solution**: Check if there's an organization-level settings page

3. **Permissions**: Your account might not have permission to create PATs
   - **Solution**: Contact your organization admin or Supabase support

4. **Feature Not Available**: PATs might not be available in your region/plan
   - **Solution**: Check Supabase documentation or contact support

### Alternative: Check Supabase Documentation

1. Go to: https://supabase.com/docs/reference/api/start
2. Look for "Personal Access Tokens" section
3. Follow the official documentation links

## After Creating the PAT

Once you have the PAT, store it in your database:

```sql
-- Store PAT in app_config table
INSERT INTO app_config (key, value, description, updated_at)
VALUES (
  'supabase_access_token',
  'sbp_your_pat_token_here',  -- Replace with your actual PAT
  'Personal Access Token for Supabase Management API (used to update Edge Function secrets)',
  NOW()
)
ON CONFLICT (key) DO UPDATE 
SET value = EXCLUDED.value, 
    description = EXCLUDED.description,
    updated_at = NOW();
```

## Visual Guide

```
Supabase Dashboard
  └─ Profile Icon (top-right)
      └─ Account Preferences / Account Settings
          └─ Access Tokens (tab/section)
              └─ Generate New Token
                  └─ Copy Token (shown only once!)
```

## Troubleshooting

### "I don't see Access Tokens option"

1. Make sure you're in **Account Settings**, not Project Settings
2. Try different tabs in Account Settings
3. Check if you're using an organization account (might be in org settings)

### "Token generation is disabled"

- Your account might not have permission
- Contact Supabase support: https://supabase.com/support

### "I lost my token"

- PATs can only be viewed once when created
- You'll need to generate a new one
- Revoke the old one if you think it's compromised

## Security Reminders

- ⚠️ **PATs have full access** to your Supabase account
- ⚠️ **Never commit PATs** to git or share them publicly
- ⚠️ **Store securely** - use environment variables or secure storage
- ⚠️ **Revoke old tokens** if you suspect they're compromised

