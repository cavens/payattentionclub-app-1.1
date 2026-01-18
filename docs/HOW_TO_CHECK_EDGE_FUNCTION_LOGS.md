# How to Check Edge Function Logs in Supabase Dashboard

## Step-by-Step Instructions

### 1. Navigate to Edge Functions
1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions
   - Or: Dashboard → Your Project → Edge Functions (left sidebar)

### 2. Find preview-service
1. Look for `preview-service` in the list of functions
2. Click on `preview-service` to open its details

### 3. View Logs
1. Click on the **"Logs"** tab (usually at the top of the function details page)
2. You should see a list of recent invocations

### 4. What to Look For
Look for log entries that contain:
```
preview-service: Testing mode: true (checked from database/env var)
```
or
```
preview-service: Testing mode: false (checked from database/env var)
```

### 5. Filter Logs (Optional)
- Use the search/filter box to search for: `Testing mode`
- This will show only log entries related to mode checking

### 6. Verify the Mode Value
- The log should show the **current mode** from the database
- If `app_config.testing_mode = 'true'`, logs should show: `Testing mode: true`
- If `app_config.testing_mode = 'false'`, logs should show: `Testing mode: false`

## Alternative: Trigger preview-service to Generate Logs

If you don't see recent logs, you can trigger the function:

### Option 1: Use the Test Script
```bash
cd /Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1
deno run --allow-net --allow-env --allow-read scripts/test_priority_1_mode_checking.ts
```

### Option 2: Use curl (if function is public)
```bash
curl -X POST https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/preview-service \
  -H "Content-Type: application/json" \
  -d '{
    "limitMinutes": 60,
    "penaltyPerMinuteCents": 100,
    "appCount": 1,
    "appsToLimit": {
      "app_bundle_ids": ["test.app"],
      "categories": []
    }
  }'
```

### Option 3: Use Your iOS App
- Open the app
- Navigate to the preview screen
- This will trigger `preview-service` and generate logs

## Expected Log Output

When Priority 1 is working correctly, you should see:

```
preview-service: Testing mode: true (checked from database/env var)
preview-service: Calculated deadline date: 2026-01-18 (testing mode: true)
```

Or in normal mode:

```
preview-service: Testing mode: false (checked from database/env var)
preview-service: Calculated deadline date: 2026-01-19 (testing mode: false)
```

## Troubleshooting

### No Logs Appearing?
1. Make sure the function was actually invoked (check the "Invocations" count)
2. Wait a few seconds - logs can take 10-30 seconds to appear
3. Refresh the page
4. Check if you're looking at the correct function

### Logs Show Wrong Mode?
1. Check `app_config.testing_mode` in the database:
   ```sql
   SELECT value FROM app_config WHERE key = 'testing_mode';
   ```
2. If the database value doesn't match the logs, Priority 1 might not be working correctly
3. Verify the function code uses `getTestingMode()` helper

### Can't Find the Logs Tab?
- Some Supabase projects might have logs in a different location
- Try: Dashboard → Logs → Edge Functions
- Or: Dashboard → Monitoring → Logs

