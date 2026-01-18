# Investigation Report - Testing Mode Issues
**Date**: 2026-01-17  
**Commitment ID**: `7aaba52d-14ef-4ea2-b784-56cba49c919f`

---

## Summary of Findings

### ✅ What's Working
1. **Database Testing Mode**: Enabled in `app_config` table (`testing_mode = true`)
2. **Commitment Created**: Successfully created with testing mode settings
3. **Payment Method**: Saved successfully
4. **3-Minute Timer**: Working (user confirmed)

### ❌ Issues Found

#### 1. **`week_end_timestamp` is NULL** (Critical)
- **Expected**: `2026-01-17T13:44:20.108Z` (3 minutes after creation)
- **Actual**: `NULL`
- **Impact**: Settlement will use fallback calculation (less precise)

#### 2. **Usage Data Discrepancy** (Medium)
- **User Reports**: 4 minutes used
- **Database Shows**: 0 minutes used
- **Possible Causes**:
  - Usage sync didn't record correctly
  - Query not finding the right record
  - Usage recorded but not synced to backend

#### 3. **Penalty Record Not Found** (Medium)
- **Expected**: Penalty record should exist for week `2026-01-19`
- **Actual**: No record found
- **Note**: Verification showed a penalty record earlier, but query didn't find it

---

## Detailed Analysis

### 1. Testing Mode Status

**Database Config**:
- ✅ `app_config.testing_mode = 'true'`
- ✅ Updated: `2026-01-17T13:29:08.314+00:00`

**Edge Function Secrets**:
- ⚠️ **Cannot verify via API** - Must check manually in Supabase Dashboard
- **Location**: Project Settings → Edge Functions → `super-service` → Settings → Secrets
- **Required**: `TESTING_MODE=true`

**Root Cause Hypothesis**:
The `week_end_timestamp` is NULL because `TESTING_MODE` environment variable is not set in the `super-service` Edge Function secrets. Even though the database has testing mode enabled, the Edge Function checks the environment variable first.

---

### 2. Usage Data Analysis

**Database Query Results**:
```
Date: 2026-01-17
Used Minutes: 0
Exceeded Minutes: 0
Penalty Cents: 0
Reported At: 2026-01-17T13:41:21.996984+00:00
```

**User Reports**:
- 4 minutes used
- App shows penalty calculation: $3.29

**Calculation Check**:
- 4 minutes over limit (4 - 1 = 3 minutes over)
- 3 minutes × $1.09/min = $3.27
- **Close match!** ($3.29 vs $3.27 - slight rounding difference)

**Possible Explanations**:
1. Usage was synced but the database record shows 0 (sync issue)
2. Usage is stored in a different record (wrong date or commitment)
3. App is calculating from local data, not synced to backend yet

---

### 3. Settlement Status

**Penalty Record**:
- ❌ Not found in query (but was shown in verification earlier)
- **Possible Issue**: Query uses `week_start_date = week_end_date` from commitment
- Commitment has `week_end_date = 2026-01-19`
- Need to verify penalty record uses correct week_start_date

**Settlement Status**:
- ⏳ Unknown - need to check if settlement has run
- If settlement hasn't run, penalty won't be calculated yet

---

## Root Cause: `week_end_timestamp` Issue

### Code Analysis

**File**: `supabase/functions/super-service/index.ts`

**Line 103**:
```typescript
const deadlineTimestampForRPC = TESTING_MODE ? formatDeadlineDate(deadline) : null;
```

**Line 121**:
```typescript
p_deadline_timestamp: deadlineTimestampForRPC  // Precise timestamp (testing mode) or NULL (normal mode)
```

**Analysis**:
- Code looks correct ✅
- If `TESTING_MODE` is `false` or `undefined`, `deadlineTimestampForRPC` will be `null`
- This explains why `week_end_timestamp` is NULL

**Solution**:
1. Set `TESTING_MODE=true` in Supabase Dashboard for `super-service` Edge Function
2. OR: Update `super-service` to also check database `app_config` table (like `testing-command-runner` does)

---

## Recommendations

### Immediate Actions

1. **Set TESTING_MODE in Edge Function Secrets** (High Priority)
   - Go to Supabase Dashboard
   - Project Settings → Edge Functions → `super-service` → Settings → Secrets
   - Add/Update: `TESTING_MODE=true`
   - Redeploy `super-service` function

2. **Verify Usage Data** (Medium Priority)
   - Check all usage records for this user/commitment
   - Verify if usage was synced correctly
   - Check if there are multiple usage entries

3. **Check Settlement Status** (Medium Priority)
   - Verify if settlement has run
   - Check penalty record with correct week_start_date
   - Manually trigger settlement if needed

### Long-term Fixes

1. **Update `super-service` to Check Database Config**
   - Similar to `testing-command-runner`
   - Check both environment variable AND `app_config` table
   - This ensures consistency

2. **Add Logging**
   - Log `TESTING_MODE` value in `super-service`
   - Log `deadlineTimestampForRPC` value
   - This will help debug future issues

---

## Next Steps

1. ✅ Check if `TESTING_MODE=true` is set in `super-service` secrets
2. ✅ Verify usage data (check all records, not just one)
3. ✅ Check settlement status (has it run?)
4. ✅ Fix `week_end_timestamp` issue (set TESTING_MODE or update code)

---

## Verification Queries

### Check all usage records:
```sql
SELECT * FROM public.daily_usage 
WHERE user_id = '414389a9-d44e-4603-a4bf-e4160c733bc4'
  AND commitment_id = '7aaba52d-14ef-4ea2-b784-56cba49c919f'
ORDER BY date DESC, reported_at DESC;
```

### Check penalty record:
```sql
SELECT * FROM public.user_week_penalties 
WHERE user_id = '414389a9-d44e-4603-a4bf-e4160c733bc4'
  AND week_start_date = '2026-01-19'
ORDER BY created_at DESC;
```

### Check if settlement has run:
```sql
SELECT * FROM public.user_week_penalties 
WHERE user_id = '414389a9-d44e-4603-a4bf-e4160c733bc4'
  AND settlement_status != 'pending'
ORDER BY created_at DESC;
```


