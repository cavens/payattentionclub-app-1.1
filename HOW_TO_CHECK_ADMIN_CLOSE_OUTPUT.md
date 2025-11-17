# How to Check admin-close-week-now Output

## Where Output Appears

The `admin-close-week-now` function calls `weekly-close` and returns the result. Output can be found in:

### 1. Function Response (If called via API)
If you called it via HTTP request, the response body contains the result from `weekly-close`:
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

### 2. Supabase Dashboard Logs
1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/logs/edge-functions
2. Select `admin-close-week-now` or `weekly-close` from the dropdown
3. Check recent logs for:
   - `console.log("Closing week with deadline:", deadlineStr)`
   - Any errors
   - PaymentIntent creation logs

### 3. Check via Supabase Dashboard
1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
2. Click on `admin-close-week-now`
3. Click "View logs" or "Invoke" to see output

---

## How to Call It Properly

### Via Supabase Dashboard (Easiest)
1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
2. Click on `admin-close-week-now`
3. Click "Invoke function"
4. Select "POST" method
5. Add Authorization header with your JWT token
6. Click "Invoke"
7. See response in the output panel

### Via curl (Terminal)
```bash
curl -X POST \
  'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/admin-close-week-now' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{}'
```

### Via Supabase Client (from your app)
```typescript
const { data, error } = await supabase.functions.invoke('admin-close-week-now', {
  body: {}
});
console.log('Result:', data);
```

---

## Requirements

1. **Authentication:** Must include Authorization header with valid JWT
2. **Test User:** User must have `is_test_user = true` in `users` table
3. **POST Method:** Must use POST request

---

## What to Check

1. **Did it run?** Check logs for "Closing week with deadline:"
2. **Any errors?** Check logs for error messages
3. **Did it find commitments?** Check if `poolTotalCents` > 0
4. **Did it charge users?** Check `chargedUsers` count

---

## Troubleshooting

### No Output at All
- Check if function was invoked successfully
- Check Supabase Dashboard logs
- Verify authentication token is valid

### Function Returns Error
- Check if user has `is_test_user = true`
- Check if Authorization header is present
- Check logs for specific error messages

### Function Runs But No Results
- Check if there are commitments for the week being closed
- Check if `week_end_date` matches the calculated deadline
- Verify there's data in `daily_usage` or `commitments` tables


