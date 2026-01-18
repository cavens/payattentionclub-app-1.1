# Personal Access Token (PAT) Setup and Flow

## Important Clarification

**Supabase's Internal Storage**: Supabase does not publicly document where Personal Access Tokens are stored internally in their infrastructure. This is managed by Supabase's backend systems.

**Our Application's Storage**: In our application, we store the PAT in our own **`app_config` database table** so that our Edge Functions can access it to call the Management API. This is our application's choice for where to store the PAT.

## Where We Store the PAT in Our Application

The Personal Access Token is stored in our **`app_config` database table** with the key `supabase_access_token`:

```sql
-- Store PAT in app_config table
INSERT INTO app_config (key, value, description, updated_at)
VALUES (
  'supabase_access_token',
  'your-pat-token-here',
  'Personal Access Token for Supabase Management API (used to update Edge Function secrets)',
  NOW()
)
ON CONFLICT (key) DO UPDATE 
SET value = EXCLUDED.value, 
    updated_at = NOW();
```

**Location**: Database table `public.app_config`, not in Edge Function secrets.

## How the Dashboard Toggle Works

### Step-by-Step Flow:

1. **User clicks toggle button** in dashboard (`testing-dashboard.html`)
   ```javascript
   // Line 817-860 in testing-dashboard.html
   async function toggleTestingMode() {
     // Calls testing-command-runner with toggle_testing_mode command
   }
   ```

2. **Dashboard calls `testing-command-runner` Edge Function**
   ```javascript
   POST /functions/v1/testing-command-runner
   Body: { command: "toggle_testing_mode" }
   ```

3. **`testing-command-runner` updates `app_config.testing_mode`**
   ```typescript
   // Lines 340-371 in testing-command-runner/index.ts
   // Step 1: Update app_config table
   await supabase.from('app_config').upsert({
     key: 'testing_mode',
     value: newValue, // 'true' or 'false'
   });
   ```

4. **`testing-command-runner` calls `update-secret` Edge Function**
   ```typescript
   // Lines 372-401 in testing-command-runner/index.ts
   // Step 2: Update TESTING_MODE Edge Function secret
   const updateSecretUrl = `${supabaseUrl}/functions/v1/update-secret`;
   await fetch(updateSecretUrl, {
     method: 'POST',
     body: JSON.stringify({
       secretName: 'TESTING_MODE',
       secretValue: newValue,
     }),
   });
   ```

5. **`update-secret` reads PAT from `app_config`**
   ```typescript
   // Lines 107-121 in update-secret/index.ts
   const { data: tokenConfig } = await supabase
     .from('app_config')
     .select('value')
     .eq('key', 'supabase_access_token')
     .single();
   
   const accessToken = tokenConfig?.value;
   ```

6. **`update-secret` uses PAT to call Management API**
   ```typescript
   // Lines 123-145 in update-secret/index.ts
   const managementApiUrl = `https://api.supabase.com/v1/projects/${projectRef}/secrets`;
   await fetch(managementApiUrl, {
     method: 'POST',
     headers: {
       'Authorization': `Bearer ${accessToken}`, // PAT from app_config
     },
     body: JSON.stringify({
       name: 'TESTING_MODE',
       value: 'true' or 'false',
     }),
   });
   ```

7. **Management API updates the Edge Function secret**
   - Updates `TESTING_MODE` secret in Supabase Dashboard
   - All Edge Functions can now read the updated value via `Deno.env.get('TESTING_MODE')`

## Setup Instructions

### 1. Generate Personal Access Token

1. Go to: https://supabase.com/dashboard/account/tokens
2. Click "Generate new token"
3. Give it a name (e.g., "Edge Function Secret Updater")
4. Copy the token (you'll only see it once!)

### 2. Store PAT in Database

Run this SQL script (or use the helper script below):

```sql
-- Store PAT in app_config
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

### 3. Verify Setup

Check that PAT is stored:

```sql
SELECT key, 
       CASE 
         WHEN key = 'supabase_access_token' THEN '***HIDDEN***'
         ELSE value
       END AS value,
       description,
       updated_at
FROM app_config
WHERE key = 'supabase_access_token';
```

### 4. Test the Toggle

1. Open the testing dashboard
2. Click the "Testing Mode" toggle
3. Check the response - it should show:
   ```json
   {
     "success": true,
     "testing_mode": true,
     "app_config_updated": true,
     "secret_updated": true  // ✅ This should be true if PAT works
   }
   ```

## What Happens Without PAT?

If PAT is **not** set in `app_config`:

1. ✅ `app_config.testing_mode` still updates successfully
2. ❌ Edge Function secret `TESTING_MODE` update fails
3. ⚠️ Function returns a warning:
   ```json
   {
     "warning": "⚠️ Testing mode updated in database, but Edge Function secret update failed. Please update TESTING_MODE manually..."
   }
   ```
4. 📝 User must manually update `TESTING_MODE` in Supabase Dashboard

## Security Notes

- **PAT is stored in our database** (`app_config` table), not in Edge Function secrets
- **PAT has full access** to your Supabase account - keep it secure!
- **Only authorized users** should have access to the `app_config` table
- **Consider using Row Level Security (RLS)** on `app_config` table if needed
- **Note**: This is where WE store the PAT in our application. Supabase stores PATs internally in their own systems (location not publicly documented)

## Troubleshooting

### PAT not working?

1. **Check PAT is stored**:
   ```sql
   SELECT key, value IS NOT NULL as has_value
   FROM app_config
   WHERE key = 'supabase_access_token';
   ```

2. **Check PAT is valid**:
   - Go to https://supabase.com/dashboard/account/tokens
   - Verify the token hasn't been revoked
   - Generate a new one if needed

3. **Check function logs**:
   - Go to Supabase Dashboard → Edge Functions → update-secret → Logs
   - Look for errors about "JWT could not be decoded" or "Unauthorized"

4. **Verify Management API access**:
   - PAT needs permissions to update project secrets
   - Some PATs may have limited scopes

