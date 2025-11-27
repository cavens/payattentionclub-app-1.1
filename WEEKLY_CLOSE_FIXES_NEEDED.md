# Weekly Close - Fixes Needed

## Current Status Check

✅ **Database Schema** - Already verified  
✅ **Date Logic Understanding** - Documented in REMINDER_WEEK_DATES.md  
❌ **Date Logic Implementation** - **NEEDS FIX** (weekly-close function still uses wrong field)  
❌ **Daily Usage Aggregation** - **NEEDS FIX** (not filtering by week)  
⚠️ **Stripe Key** - Using STRIPE_SECRET_KEY, but should use STRIPE_SECRET_KEY_TEST with fallback

---

## Issue 1: Wrong Week Identification Field ❌

**Problem:** Function uses `week_start_date` to identify weeks, but should use `week_end_date` (deadline)

**Why:** 
- `week_start_date` = when user committed (varies per user)
- `week_end_date` = deadline (next Monday - same for all users in that week)
- To find all commitments for "this week", we need to match by `week_end_date` (deadline)

**Current Code (WRONG):**
```typescript
// Line 36: Finding revoked commitments
.eq("week_start_date", weekStartStr)  // ❌ WRONG

// Line 83: Finding users for this week
.eq("week_start_date", weekStartStr)  // ❌ WRONG

// Line 123: Updating weekly_pools
.eq("week_start_date", weekStartStr)  // ❌ WRONG

// Line 129: Finding penalties
.eq("week_start_date", weekStartStr)  // ❌ WRONG
```

**Should Be:**
```typescript
// Use week_end_date (deadline) instead
.eq("week_end_date", weekEndStr)  // ✅ CORRECT
```

**Also:** The function calculates `weekStartStr` as "7 days ago", but it should calculate the deadline (next Monday) that just passed.

---

## Issue 2: Daily Usage Aggregation Not Filtered by Week ❌

**Problem:** Line 94 gets ALL daily_usage for a user, not filtered by week

**Current Code (WRONG):**
```typescript
// Line 94: Gets ALL daily_usage for user
const { data: userDaily } = await supabase
  .from("daily_usage")
  .select("penalty_cents, commitment_id")
  .eq("user_id", userId);  // ❌ No week filtering!

// Line 103: Sums ALL penalties (could include other weeks!)
const totalPenalty = (userDaily ?? []).reduce((sum, row) => 
  sum + (row.penalty_cents ?? 0), 0);
```

**Fix Needed:**
1. Get commitment_ids for this week first (from the commitments query)
2. Filter daily_usage by those commitment_ids

**Should Be:**
```typescript
// Get commitment IDs for this week (from earlier query)
const commitmentIds = userIdsRes
  .filter(c => c.week_end_date === weekEndStr)
  .map(c => c.id);

// Filter daily_usage by commitment_id
const { data: userDaily } = await supabase
  .from("daily_usage")
  .select("penalty_cents, commitment_id")
  .eq("user_id", userId)
  .in("commitment_id", commitmentIds);  // ✅ Filter by week
```

---

## Issue 3: Stripe Key Should Use Test Key ⚠️

**Current Code:**
```typescript
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
```

**Should Be (like billing-status):**
```typescript
// Priority: STRIPE_SECRET_KEY_TEST (if exists) → STRIPE_SECRET_KEY (fallback)
const STRIPE_SECRET_KEY_TEST = Deno.env.get("STRIPE_SECRET_KEY_TEST");
const STRIPE_SECRET_KEY_PROD = Deno.env.get("STRIPE_SECRET_KEY");
const STRIPE_SECRET_KEY = STRIPE_SECRET_KEY_TEST || STRIPE_SECRET_KEY_PROD;
```

---

## Fix Priority

1. **HIGH:** Fix week identification (use `week_end_date` instead of `week_start_date`)
2. **HIGH:** Fix daily usage aggregation (filter by commitment_ids for this week)
3. **MEDIUM:** Update Stripe key to use test key with fallback

---

## Next Steps

1. Fix the `weekly-close/index.ts` function with these changes
2. Test with `admin-close-week-now`
3. Deploy the fixed version




