# Test: Grace Period Storage (Priority 4)

> **⚠️ PRIORITY: Test this FIRST thing tomorrow (2026-01-19)**
> 
> This is Priority 4 implementation that needs to be verified after deployment.
> Ensure the function is deployed and test both testing mode and normal mode scenarios.

## Deployment

### Option 1: Supabase Dashboard (Recommended)

1. Go to **Supabase Dashboard → SQL Editor**
2. Copy the entire contents of `supabase/remote_rpcs/rpc_create_commitment.sql`
3. Paste and execute in the SQL Editor
4. Verify success: Should see "Success. No rows returned"

### Option 2: Supabase CLI

```bash
cd payattentionclub-app-1.1
supabase db execute --file supabase/remote_rpcs/rpc_create_commitment.sql
```

---

## Testing Instructions

### Prerequisites

1. Ensure you have test user set up (or use `rpc_setup_test_data()`)
2. Know your test user ID (default: `11111111-1111-1111-1111-111111111111`)

### Test 1: Testing Mode (Grace Period = 1 minute)

**Step 1: Enable Testing Mode**
```sql
UPDATE public.app_config
SET value = 'true'
WHERE key = 'testing_mode';
```

**Step 2: Create Commitment with deadline_timestamp**
```sql
-- Set session to test user (if using rpc_setup_test_data)
SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- Create commitment
SELECT public.rpc_create_commitment(
  p_deadline_date := CURRENT_DATE,
  p_limit_minutes := 30,
  p_penalty_per_minute_cents := 100,
  p_app_count := 1,
  p_apps_to_limit := '["com.example.app"]'::jsonb,
  p_saved_payment_method_id := 'pm_test_123',
  p_deadline_timestamp := NOW() + INTERVAL '3 minutes'  -- Testing mode: 3 min deadline
);
```

**Step 3: Verify Grace Period**
```sql
SELECT 
  id,
  week_end_date,
  week_end_timestamp,
  week_grace_expires_at,
  EXTRACT(EPOCH FROM (week_grace_expires_at - week_end_timestamp)) / 60 AS grace_period_minutes,
  created_at
FROM public.commitments
WHERE user_id = '11111111-1111-1111-1111-111111111111'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected Result:**
- ✅ `week_end_timestamp` is NOT NULL (the deadline timestamp)
- ✅ `week_grace_expires_at` is NOT NULL
- ✅ `grace_period_minutes` = **1.0** (exactly 1 minute)

---

### Test 2: Normal Mode (Grace Period = Tuesday 12:00 ET)

**Step 1: Disable Testing Mode**
```sql
UPDATE public.app_config
SET value = 'false'
WHERE key = 'testing_mode';
```

**Step 2: Calculate Next Monday**
```sql
-- Calculate next Monday date
SELECT 
  CURRENT_DATE + (8 - EXTRACT(DOW FROM CURRENT_DATE)::int) % 7 AS next_monday;
```

**Step 3: Create Commitment WITHOUT deadline_timestamp**
```sql
-- Set session to test user
SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- Create commitment (normal mode)
SELECT public.rpc_create_commitment(
  p_deadline_date := (SELECT CURRENT_DATE + (8 - EXTRACT(DOW FROM CURRENT_DATE)::int) % 7),  -- Next Monday
  p_limit_minutes := 30,
  p_penalty_per_minute_cents := 100,
  p_app_count := 1,
  p_apps_to_limit := '["com.example.app"]'::jsonb,
  p_saved_payment_method_id := 'pm_test_123',
  p_deadline_timestamp := NULL  -- Normal mode: no timestamp
);
```

**Step 4: Verify Grace Period**
```sql
SELECT 
  id,
  week_end_date,
  week_end_timestamp,
  week_grace_expires_at,
  -- Calculate hours between Monday 12:00 ET and Tuesday 12:00 ET
  EXTRACT(EPOCH FROM (
    week_grace_expires_at - 
    (week_end_date::timestamp AT TIME ZONE 'America/New_York' + INTERVAL '12 hours')
  )) / 3600 AS grace_period_hours,
  created_at
FROM public.commitments
WHERE user_id = '11111111-1111-1111-1111-111111111111'
  AND week_end_timestamp IS NULL  -- Normal mode commitment
ORDER BY created_at DESC
LIMIT 1;
```

**Expected Result:**
- ✅ `week_end_timestamp` is NULL (normal mode)
- ✅ `week_grace_expires_at` is NOT NULL
- ✅ `grace_period_hours` ≈ **24.0** (approximately 24 hours, accounting for DST)

**Additional Check: Verify it's Tuesday 12:00 ET**
```sql
SELECT 
  week_grace_expires_at AT TIME ZONE 'America/New_York' AS grace_expires_et,
  EXTRACT(DOW FROM week_grace_expires_at AT TIME ZONE 'America/New_York') AS day_of_week,
  EXTRACT(HOUR FROM week_grace_expires_at AT TIME ZONE 'America/New_York') AS hour_et
FROM public.commitments
WHERE user_id = '11111111-1111-1111-1111-111111111111'
  AND week_end_timestamp IS NULL
ORDER BY created_at DESC
LIMIT 1;
```

**Expected:**
- ✅ `day_of_week` = **2** (Tuesday, where 0=Sunday, 1=Monday, 2=Tuesday)
- ✅ `hour_et` = **12** (noon)

---

### Test 3: Settlement Function Uses Stored Value

**Verify that settlement function will use the stored `week_grace_expires_at`:**

The settlement function (`bright-service/index.ts`) already checks for `week_grace_expires_at` first:

```typescript
const explicit = candidate.commitment.week_grace_expires_at;
if (explicit) {
  return new Date(explicit).getTime() <= reference.getTime();
}
```

**To verify it's being used:**

1. Create a commitment (use Test 1 or Test 2 above)
2. Wait for grace period to expire (or manually check)
3. Run settlement and check logs - it should use the stored value

**Quick Check:**
```sql
-- Check if settlement would use stored value
SELECT 
  c.id,
  c.week_grace_expires_at,
  NOW() AS current_time,
  CASE 
    WHEN c.week_grace_expires_at IS NOT NULL THEN
      CASE 
        WHEN NOW() > c.week_grace_expires_at THEN 'Grace expired (would use stored value)'
        ELSE 'Grace not expired (would use stored value)'
      END
    ELSE 'No stored value (would calculate)'
  END AS settlement_behavior
FROM public.commitments c
WHERE c.user_id = '11111111-1111-1111-1111-111111111111'
ORDER BY c.created_at DESC
LIMIT 1;
```

---

## Quick Test Script

Run the complete test script:

```bash
# In Supabase Dashboard → SQL Editor, run:
```

Or use the provided test file:
```sql
-- Run: supabase/sql-drafts/test_grace_period_storage.sql
```

---

## Success Criteria

✅ **Testing Mode:**
- `week_grace_expires_at` is set
- Grace period is exactly 1 minute after deadline

✅ **Normal Mode:**
- `week_grace_expires_at` is set
- Grace period is Tuesday 12:00 ET (approximately 24 hours after Monday)

✅ **Settlement Integration:**
- Settlement function will use stored value (no runtime calculation needed)
- Eliminates potential calculation errors

---

## Troubleshooting

**Issue: `week_grace_expires_at` is NULL**
- Check that the function was deployed correctly
- Verify the INSERT statement includes `week_grace_expires_at` column
- Check function logs for errors

**Issue: Grace period is wrong duration**
- Testing mode: Should be 1 minute (60 seconds)
- Normal mode: Should be ~24 hours (accounting for DST)
- Verify timezone calculations are correct

**Issue: Settlement still calculates dynamically**
- Check that `week_grace_expires_at` is NOT NULL in database
- Verify settlement function code checks for explicit value first
- Check settlement logs to see which path it takes

