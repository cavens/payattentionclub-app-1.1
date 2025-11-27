# How to Test weekly-close Directly (No JWT Needed!)

## Good News! 🎉

The `weekly-close` function **doesn't require user authentication** - it uses the service role key internally. You can call it directly!

---

## Method 1: Via Supabase Dashboard (Easiest) ⭐

1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
2. Click on **`weekly-close`** (not admin-close-week-now)
3. Click **"Invoke function"**
4. Method: **POST**
5. **Headers:** Leave empty (or add `Content-Type: application/json`)
6. **Body:** `{}` (empty JSON object)
7. Click **"Invoke"**
8. **See the output directly!**

### Expected Response

```json
{
  "weekDeadline": "2024-11-18",
  "poolTotalCents": 0,
  "chargedUsers": 0,
  "succeededPayments": 0,
  "requiresActionPayments": 0,
  "failedPayments": 0,
  "results": []
}
```

**No JWT token needed!** ✅

---

## Method 2: Via curl (Terminal)

```bash
curl -X POST \
  'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Get your service role key:**
- Supabase Dashboard → Settings → API
- Copy the **"service_role"** key (not anon key!)

**Note:** Service role key bypasses RLS, so be careful!

---

## Method 3: Via Supabase Dashboard (Using Service Role)

1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
2. Click `weekly-close`
3. Click "Invoke function"
4. In **Headers**, add:
   ```
   Authorization: Bearer YOUR_SERVICE_ROLE_KEY
   ```
5. Body: `{}`
6. Click "Invoke"

---

## Why admin-close-week-now Requires JWT

The `admin-close-week-now` function is a **safety wrapper** that:
- Checks if user is authenticated
- Verifies user is a test user (`is_test_user = true`)
- Then calls `weekly-close`

But for **direct testing**, you can skip it and call `weekly-close` directly!

---

## Comparison

| Method | JWT Needed? | Test User Check? | Easiest? |
|--------|-------------|------------------|----------|
| `weekly-close` (direct) | ❌ No | ❌ No | ✅ Yes |
| `admin-close-week-now` | ✅ Yes | ✅ Yes | ❌ No |

---

## Recommended: Use weekly-close Directly

**For testing purposes:**
1. Go to Supabase Dashboard → Functions → `weekly-close`
2. Click "Invoke function"
3. POST with empty body `{}`
4. See output immediately!

**No authentication needed!** 🎉

---

## What You'll See

The response shows:
- `weekDeadline`: Which week was closed (deadline date)
- `poolTotalCents`: Total penalty pool amount
- `chargedUsers`: How many users were charged
- `succeededPayments`: Successful payments
- `requiresActionPayments`: Payments needing 3D Secure
- `failedPayments`: Failed payments
- `results`: Detailed results per user

---

## Troubleshooting

### "Use POST" Error
- Make sure method is POST, not GET

### Empty Response
- Check Supabase Dashboard → Functions → `weekly-close` → Logs
- Look for error messages or console.log output

### No Data Found
- Check if there are commitments for the week being closed
- Check if `week_end_date` matches the calculated deadline
- Verify data exists in `commitments` and `daily_usage` tables

---

## Next Steps After Testing

Once you see the output:
1. Verify `weekDeadline` is correct
2. Check if `poolTotalCents` matches expected values
3. Verify database was updated (`weekly_pools`, `user_week_penalties`, `payments`)
4. Check logs for any errors




