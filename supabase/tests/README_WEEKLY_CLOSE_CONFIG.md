# Weekly Close Function Configuration

## Issue

The `weekly-close` Edge Function tests require JWT verification to be disabled in the Supabase dashboard. This is because `weekly-close` is an admin function that uses the service role key internally and doesn't require user authentication.

## Solution

### For Local Development

The `config.toml` file already includes:
```toml
[functions.weekly-close]
verify_jwt = false
```

This configuration is automatically applied when running Supabase locally.

### For Remote Projects (Staging/Production)

You must manually configure this in the Supabase Dashboard:

1. Go to: **Supabase Dashboard** → **Edge Functions** → **weekly-close**
2. Click on **Settings** (or the gear icon)
3. Find the **"Verify JWT"** option
4. **Disable** JWT verification (set to `false`)
5. Save the changes

### Alternative: Use admin-close-week-now

Instead of calling `weekly-close` directly, you can use the `admin-close-week-now` function which:
- Requires a valid user JWT
- Verifies the user is a test user (`is_test_user = true`)
- Then calls `weekly-close` internally

This approach maintains security while allowing tests to work.

## Current Status

- ✅ Local config.toml configured
- ⚠️ Remote project needs manual configuration
- ✅ Test helper updated to include required headers

## Testing

After configuring JWT verification to `false` in the Supabase dashboard, the `test_weekly_close.ts` tests should pass.

