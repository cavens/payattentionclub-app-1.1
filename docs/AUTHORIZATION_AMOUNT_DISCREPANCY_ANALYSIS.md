# Authorization Amount Discrepancy Analysis
**Date**: 2026-01-17  
**Issue**: User reports authorizing $200-300, but commitment shows $15.00

---

## The Discrepancy

**User Reports**: Authorized $200-300 when creating commitment  
**Database Shows**: `max_charge_cents: 1500` = $15.00  
**Question**: Why the difference?

---

## Analysis

### Current Commitment Data

**Commitment ID**: `fb68a996-3e6d-4e7a-a931-f588afba3c6b`
- **Created**: `2026-01-17T14:15:33`
- **Deadline**: `2026-01-17T14:18:33` (3 minutes later - testing mode)
- **Limit**: 1 minute
- **Penalty Rate**: $0.58/min (58 cents/min)
- **App Count**: 1 app
- **Max Charge (stored)**: $15.00 (1500 cents)

### Why $15.00 Appears

**Calculation at Creation Time** (with 3 minutes remaining):
1. Minutes Remaining: 3 minutes
2. Days Remaining: 3 / 1440 = 0.002 days
3. Max Usage Minutes: 0.002 × 720 = 1.44 minutes
4. Potential Overage: max(0, 1.44 - 1) = 0.44 minutes
5. Strictness Ratio: 1.44 / 1 = 1.44
6. Strictness Multiplier: min(10.0, 1.44 × 0.4) = 0.576
7. Base Amount: 0.44 × 58 × 0.576 = 14.7 cents
8. After factors: 14.7 × 1.0 × 1.0 = 14.7 cents
9. After damping (0.026): 14.7 × 0.026 = 0.38 cents
10. **After minimum**: max(1500, 0.38) = **1500 cents = $15.00**

**Result**: The calculated amount ($0.0038) was below the $15 minimum, so it was capped at $15.00.

---

## Why User Saw $200-300

### Possible Explanations

#### 1. **Different Commitment** (Most Likely)
- User might be looking at a different commitment
- Previous commitment might have had different settings (higher limit, more apps, higher penalty)
- That commitment would have calculated to $200-300

#### 2. **Display Issue in App**
- App might be showing a cached or incorrect value
- App might be showing a preview amount instead of actual authorization
- App might be showing a different commitment's amount

#### 3. **Stripe Shows Different Amount**
- Stripe authorization might show a different amount than what's stored
- Could be a hold amount vs. actual authorization
- Could be showing a previous authorization

#### 4. **Calculation Was Different at Creation**
- If settings were different at creation time, calculation would be different
- But this seems unlikely - settings are stored in commitment

---

## The $15 Minimum Issue

### Current Minimum: $15.00

**Location**: `calculate_max_charge_cents.sql` line 101
```sql
v_result_cents := GREATEST(1500, LEAST(100000, FLOOR(v_base_amount_cents)::integer));
```

**User's Request**: Change minimum back to $5.00

### Why $15 is Relevant Here

**In Testing Mode**:
- With only 3 minutes remaining, the calculation is very small
- It almost always hits the minimum ($15)
- This is why we see $15 instead of a calculated amount

**In Normal Mode**:
- With 7 days remaining, calculations are much larger
- Usually don't hit the minimum
- Would show $200-300 for typical settings

---

## Recommendation

### 1. **Change Minimum Back to $5.00** (As Requested)

**Action**: Update `calculate_max_charge_cents.sql` to use $5.00 (500 cents) minimum instead of $15.00

**Impact**:
- Testing mode commitments will show $5.00 instead of $15.00
- Normal mode commitments below $5.00 will show $5.00 (rare)
- Most normal mode commitments will still be $200-300+ (unaffected)

**Files to Update**:
- `supabase/remote_rpcs/calculate_max_charge_cents.sql` (line 49, 101)
- Migration file to apply the change

### 2. **Investigate the $200-300 Authorization**

**Questions to Answer**:
1. Was this a different commitment?
2. What were the settings for that commitment? (limit, penalty, apps)
3. Was it created in normal mode (7-day deadline) vs. testing mode (3-minute deadline)?
4. Check Stripe to see what was actually authorized

**Action**: Query all recent commitments for this user to see if there's one with $200-300 authorization

---

## Why $15 is Relevant in This Case

**Even though you authorized $200-300**:
1. **This specific commitment** (testing mode, 1-minute limit, 3-minute deadline) calculates to $15
2. **The $15 minimum** is being applied because the calculated amount is below $15
3. **If minimum was $5**, this commitment would show $5 instead
4. **The $200-300** you saw was likely from a different commitment or different settings

---

## Suggested Actions

1. **Change minimum to $5.00** (as you requested)
2. **Check other commitments** - see if there's one with $200-300 authorization
3. **Verify Stripe** - check what was actually authorized in Stripe dashboard
4. **Check app display** - verify what the app is showing vs. what's stored

---

## Next Steps

1. Should I change the minimum from $15 to $5?
2. Should I create a script to check all your recent commitments to find the $200-300 one?
3. Should I check what the app is displaying vs. what's stored?


