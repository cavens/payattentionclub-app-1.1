# Weekly Close Fixes Applied ✅

## Changes Made to `supabase/functions/weekly-close/index.ts`

### 1. ✅ Stripe Key Fix (Minor)
**Changed:** Use `STRIPE_SECRET_KEY_TEST` with fallback to `STRIPE_SECRET_KEY`

**Before:**
```typescript
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
```

**After:**
```typescript
// Priority: STRIPE_SECRET_KEY_TEST (if exists) → STRIPE_SECRET_KEY (fallback)
const STRIPE_SECRET_KEY_TEST = Deno.env.get("STRIPE_SECRET_KEY_TEST");
const STRIPE_SECRET_KEY_PROD = Deno.env.get("STRIPE_SECRET_KEY");
const STRIPE_SECRET_KEY = STRIPE_SECRET_KEY_TEST || STRIPE_SECRET_KEY_PROD;
if (!STRIPE_SECRET_KEY) {
  console.error("ERROR: No Stripe secret key found...");
}
```

---

### 2. ✅ Week Identification Fix (Critical)
**Changed:** Use `week_end_date` (deadline) instead of `week_start_date` to identify weeks

**Key Changes:**
- **Line 30-52:** Fixed deadline calculation logic
  - If today is Monday → close week ending today
  - If today is Tue-Sat → close week ending last Monday
  - If today is Sunday → close week ending tomorrow (Monday)

- **Line 56:** Find revoked commitments by `week_end_date` (deadline)
  ```typescript
  .eq("week_end_date", deadlineStr)  // ✅ Was: .eq("week_start_date", weekStartStr)
  ```

- **Line 96:** Find all commitments by `week_end_date` (deadline)
  ```typescript
  .eq("week_end_date", deadlineStr)  // ✅ Was: .eq("week_start_date", weekStartStr)
  ```

- **Line 138:** Update weekly_pools by deadline
  ```typescript
  .eq("week_start_date", deadlineStr)  // ✅ Uses deadline (legacy naming)
  ```

- **Line 145:** Find penalties by deadline
  ```typescript
  .eq("week_start_date", deadlineStr)  // ✅ Uses deadline (legacy naming)
  ```

- **Line 308:** Close pool by deadline
  ```typescript
  .eq("week_start_date", deadlineStr)  // ✅ Uses deadline (legacy naming)
  ```

**Why:** `week_end_date` (deadline) groups commitments by week, while `week_start_date` varies per user.

---

### 3. ✅ Daily Usage Aggregation Fix (Critical)
**Changed:** Filter daily_usage by commitment_ids for this week

**Before:**
```typescript
// Got ALL daily_usage for user (could include other weeks!)
const { data: userDaily } = await supabase
  .from("daily_usage")
  .select("penalty_cents, commitment_id")
  .eq("user_id", userId);  // ❌ No week filtering
```

**After:**
```typescript
// Get commitment IDs for this week first
const commitmentsRes = await supabase
  .from("commitments")
  .select("id, user_id")
  .eq("week_end_date", deadlineStr);
const commitmentIds = commitmentsRes.map(r => r.id);

// Filter daily_usage by commitment_ids for this week
const { data: userDaily } = await supabase
  .from("daily_usage")
  .select("penalty_cents, commitment_id")
  .eq("user_id", userId)
  .in("commitment_id", commitmentIds);  // ✅ Only this week's commitments
```

**Why:** Prevents summing penalties from multiple weeks.

---

## Summary of All Changes

| Issue | Status | Lines Changed |
|-------|--------|---------------|
| Stripe key (test with fallback) | ✅ Fixed | 3-9 |
| Week identification (use deadline) | ✅ Fixed | 30-52, 56, 96, 138, 145, 308 |
| Daily usage aggregation (filter by week) | ✅ Fixed | 94-110 |
| Response JSON (use deadline) | ✅ Fixed | 313 |

---

## Testing Checklist

Before deploying, test with `admin-close-week-now`:

- [ ] Function runs without errors
- [ ] Finds all commitments for the correct week (by deadline)
- [ ] Calculates penalties correctly (only from this week's daily_usage)
- [ ] Creates PaymentIntents for users with balance
- [ ] Updates weekly_pools correctly
- [ ] Closes the pool correctly

---

## Next Steps

1. **Test locally** (if possible) or with `admin-close-week-now`
2. **Deploy** the fixed function
3. **Verify** it works correctly
4. **Set up cron job** (if not already done)

---

## Notes

- All references to `week_start_date` in `user_week_penalties` and `weekly_pools` actually store the deadline (legacy naming)
- The function now correctly uses `week_end_date` (deadline) to identify weeks
- Daily usage is now properly filtered by commitment_ids for this week


