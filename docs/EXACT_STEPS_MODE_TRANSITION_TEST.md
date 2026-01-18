# Exact Steps: Mode Transition Test

## What You'll Do
1. Check current state
2. Toggle mode in dashboard
3. Verify it worked
4. Toggle back
5. Verify again

---

## Step 1: Check Current State

**Where**: Supabase Dashboard → SQL Editor

**What to do**:
1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/editor
2. Click "SQL Editor" (left sidebar)
3. Paste this query:
   ```sql
   SELECT key, value, updated_at 
   FROM app_config 
   WHERE key = 'testing_mode';
   ```
4. Click "Run" (or press Cmd+Enter)
5. **Note the value** (should be `"true"` or `"false"`)

**Expected result**: You see the current testing mode value

---

## Step 2: Toggle Mode in Dashboard

**Where**: Dashboard in your browser

**What to do**:
1. Go to: http://localhost:8000/testing-dashboard.html
2. Look at the top - you'll see "Testing Mode: [toggle] [status]"
3. **Click the toggle** (the checkbox)
4. Wait 2-3 seconds
5. Look at the Results panel at the bottom

**What to check**:
- Should show: `app_config: ✅ Updated`
- Should show: `secret_updated: ✅ Updated`
- Should show: `🎉 Both locations updated successfully!`

**If you see errors**: Note what they say

---

## Step 3: Verify It Worked (Database)

**Where**: Supabase Dashboard → SQL Editor

**What to do**:
1. Go back to SQL Editor (same place as Step 1)
2. Run the same query again:
   ```sql
   SELECT key, value, updated_at 
   FROM app_config 
   WHERE key = 'testing_mode';
   ```
3. **Check**: The `value` should be **different** from Step 1
   - If Step 1 was `"true"`, now it should be `"false"`
   - If Step 1 was `"false"`, now it should be `"true"`

**Expected result**: Value changed from what you saw in Step 1

---

## Step 4: Verify It Worked (Edge Function Secret)

**You're absolutely right!** Secrets are masked in the dashboard (shown as `*****`), so you can't see the actual value there.

**How to verify**:
1. **Trust Step 2's response**: If the dashboard showed `secret_updated: true`, the secret was updated! ✅
   - The `update-secret` function uses the Management API, which only returns success if it actually worked
   - If it failed, you'd see an error message

**Expected result**: Step 2 showed `secret_updated: true` ✅

**Note**: Since secrets are masked, we can't directly verify the value in the dashboard. But if `secret_updated: true` appears in Step 2, the Management API successfully updated it, so you're good to go!

---

## Step 5: Run Validation Function

**Where**: Supabase Dashboard → SQL Editor

**What to do**:
1. Go back to SQL Editor
2. Paste this query:
   ```sql
   SELECT public.rpc_validate_mode_consistency();
   ```
3. Click "Run"
4. Look at the result - it's JSON

**What to check**:
- Look for `"valid": true` ✅
- Look for `"issues": []` ✅ (empty array means no problems)
- Look for `"mode"` - should match current mode

**Expected result**: `"valid": true` and `"issues": []`

---

## Step 6: Toggle Back

**Where**: Dashboard in your browser

**What to do**:
1. Go back to: http://localhost:8000/testing-dashboard.html
2. **Click the toggle again** (to switch it back)
3. Wait 2-3 seconds
4. Check Results panel - should show success again

**Expected result**: Same success message as Step 2

---

## Step 7: Verify Again

**Where**: Supabase Dashboard → SQL Editor

**What to do**:
1. Run the query from Step 1 again:
   ```sql
   SELECT key, value, updated_at 
   FROM app_config 
   WHERE key = 'testing_mode';
   ```
2. **Check**: Value should be back to what it was in Step 1

**Expected result**: Value matches Step 1 (back to original)

---

## Step 8: Final Validation

**Where**: Supabase Dashboard → SQL Editor

**What to do**:
1. Run the validation query from Step 5 again:
   ```sql
   SELECT public.rpc_validate_mode_consistency();
   ```
2. Check result - should still show `"valid": true`

**Expected result**: Still valid

---

## Success Checklist

After completing all steps, you should have:

- [ ] Step 1: Saw current mode value
- [ ] Step 2: Toggled mode, saw success message
- [ ] Step 3: Database value changed
- [ ] Step 4: Edge Function secret matches database
- [ ] Step 5: Validation shows `valid: true`
- [ ] Step 6: Toggled back, saw success
- [ ] Step 7: Database value back to original
- [ ] Step 8: Validation still shows `valid: true`

---

## If Something Goes Wrong

### Problem: Toggle doesn't work
- Check browser console (F12) for errors
- Make sure Supabase URL and Anon Key are configured
- Check if dashboard shows any error messages

### Problem: Database updates but secret doesn't
- Check if PAT is configured (we set this up earlier)
- Check Edge Function logs: Dashboard → Functions → update-secret → Logs
- Secret might update manually - that's OK, just verify it matches

### Problem: Validation shows issues
- Look at the `issues` array in the validation result
- Each issue will tell you what's wrong
- Fix the issues it mentions

---

## That's It!

If all steps pass, the mode toggle is working correctly! 🎉

