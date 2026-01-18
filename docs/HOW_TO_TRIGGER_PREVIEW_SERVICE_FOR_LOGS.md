# How to Trigger preview-service to Generate Logs

## The Problem
`preview-service` requires authentication (JWT token), so it can't be called directly from a script without a valid user session.

## Solutions

### Option 1: Use Your iOS App (Recommended)
1. Open your iOS app
2. Navigate to the screen where you preview max charge
   - This is typically the commitment creation/preview screen
3. The app will automatically call `preview-service`
4. Wait 10-30 seconds
5. Check logs in Supabase Dashboard

### Option 2: Make preview-service Public Temporarily
If you want to test from a script, you can temporarily make it public:

1. Edit `supabase/config.toml`:
```toml
[functions.preview-service]
verify_jwt = false
```

2. Deploy the change:
```bash
supabase functions deploy preview-service
```

3. Run the trigger script:
```bash
deno run --allow-net --allow-env --allow-read scripts/trigger_preview_service.ts
```

4. **Important**: After testing, revert the change and redeploy:
```toml
# Remove or comment out:
# [functions.preview-service]
# verify_jwt = false
```

### Option 3: Check Other Functions That Use Mode Checking
Other functions that use `getTestingMode()` and might have logs:
- `bright-service` (settlement) - might have recent logs if cron ran
- `super-service` (commitment creation) - if you created a commitment recently
- `testing-command-runner` (if you used the dashboard toggle)

Check these functions' logs to verify Priority 1 is working.

### Option 4: Use Supabase Dashboard to Invoke
1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions
2. Click on `preview-service`
3. Look for an "Invoke" or "Test" button
4. If available, use it to trigger the function

## What to Look For in Logs

Once you have logs, look for:
```
preview-service: Testing mode: true (checked from database/env var)
```
or
```
preview-service: Testing mode: false (checked from database/env var)
```

The value should match your current `app_config.testing_mode` setting.

## Testing Mode Toggle

To fully test Priority 1:
1. Note current mode in database: `SELECT value FROM app_config WHERE key = 'testing_mode';`
2. Trigger preview-service (via iOS app or Option 2 above)
3. Check logs - should show current mode
4. Toggle mode in dashboard
5. Wait 2-3 seconds
6. Trigger preview-service again
7. Check logs - should show NEW mode immediately
8. This proves no stale constants are used ✅

