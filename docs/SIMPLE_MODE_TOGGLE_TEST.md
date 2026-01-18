# Simple Mode Toggle Test - Step by Step

## Goal
Test that the toggle button updates both `app_config` and Edge Function secret correctly.

---

## Step 1: Open the Dashboard

1. Open your browser
2. Go to: **http://localhost:8000/testing-dashboard.html**
   (Or whatever port the server is running on)

---

## Step 2: Configure Supabase (If Not Already Done)

1. In the dashboard, find the **"Config Section"** at the top
2. Enter:
   - **Supabase URL**: `https://auqujbppoytkeqdsgrbl.supabase.co`
   - **Supabase Anon Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF1cXVqYnBwb3l0a2VxZHNncmJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NTc4OTYsImV4cCI6MjA4MTAzMzg5Nn0.UXUQ3AXdNLUQ8yB7x_v2oQAzFz9Vj-m07l04n-6flCQ`
3. Click **"💾 Save Configuration"**
4. You should see: **"✅ Configuration saved!"**

---

## Step 3: Check Current Mode

1. Look at the top of the dashboard
2. You'll see: **"Testing Mode: [toggle] [status]"**
3. The status should show either **"ON"** or **"OFF"**
4. Note what it currently says (e.g., "ON")

---

## Step 4: Toggle the Mode

1. Click the **Testing Mode toggle** (the checkbox)
2. Wait 2-3 seconds
3. Look at the **Results panel** at the bottom of the dashboard
4. You should see a response like:

```json
{
  "success": true,
  "testing_mode": false,
  "message": "Testing mode disabled",
  "app_config_updated": true,
  "secret_updated": true,
  "secret_update_error": null,
  "warning": null
}
```

### ✅ What to Check:
- `app_config_updated: true` ✅
- `secret_updated: true` ✅ ← **This is the important one!**
- `warning: null` ✅

If `secret_updated: false`, the PAT might not be working. Check the warning message.

---

## Step 5: Verify in Database

1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/editor
2. Click **"SQL Editor"** (left sidebar)
3. Run this query:

```sql
SELECT key, value, updated_at 
FROM app_config 
WHERE key = 'testing_mode';
```

4. Check:
   - `value` should match what you toggled to (e.g., `"false"` if you turned it OFF)
   - `updated_at` should be recent (just now)

---

## Step 6: Verify Edge Function Secret (Manual Check)

1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions
2. Click **"Settings"** tab (at the top)
3. Scroll down to **"Secrets"** section
4. Find **`TESTING_MODE`** in the list
5. Check the **value**:
   - Should be `true` if testing mode is ON
   - Should be `false` if testing mode is OFF
6. **Important**: The value should match what you see in the database (Step 5)

---

## Step 7: Toggle Back

1. Go back to the dashboard
2. Click the toggle again to switch it back
3. Check the response again:
   - `app_config_updated: true` ✅
   - `secret_updated: true` ✅
4. Verify in database and Edge Function secrets again (Steps 5-6)

---

## Step 8: Run Validation Function

1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/editor
2. Click **"SQL Editor"**
3. Run this query:

```sql
SELECT public.rpc_validate_mode_consistency();
```

4. Look at the result. It should show:
   ```json
   {
     "valid": true,
     "mode": "testing",  // or "normal"
     "issues": [],
     "warnings": []
   }
   ```

5. **✅ Success if**: `valid: true` and `issues: []`

---

## What Success Looks Like

✅ Toggle button works  
✅ Response shows `secret_updated: true`  
✅ Database (`app_config`) updates  
✅ Edge Function secret (`TESTING_MODE`) updates  
✅ Both locations match  
✅ Validation function shows `valid: true`  

---

## If Something Goes Wrong

### Problem: `secret_updated: false`

**Check**:
1. Is PAT configured? Run:
   ```sql
   SELECT key, LENGTH(value) as token_length
   FROM app_config
   WHERE key = 'supabase_access_token';
   ```
   - Should show a token_length > 10

2. Check function logs:
   - Go to: Supabase Dashboard → Edge Functions → update-secret → Logs
   - Look for errors

### Problem: Toggle doesn't respond

**Check**:
1. Browser console (F12) for errors
2. Network tab to see if request was sent
3. Make sure Supabase URL and Anon Key are configured

### Problem: Database updates but secret doesn't

**This is OK temporarily**:
- Database is the source of truth
- Edge Functions will use database value on next check
- But you should fix the PAT so secret updates automatically

---

## Quick Test Checklist

- [ ] Dashboard opens
- [ ] Configuration saved
- [ ] Toggle shows current status
- [ ] Toggle changes status
- [ ] Response shows `secret_updated: true`
- [ ] Database value matches toggle
- [ ] Edge Function secret matches toggle
- [ ] Validation function shows `valid: true`
- [ ] Toggle back works
- [ ] Everything matches again

---

## That's It!

If all steps pass, the mode toggle is working correctly! 🎉

