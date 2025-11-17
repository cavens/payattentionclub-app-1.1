# Understanding week_start_date vs week_end_date

## The Confusing Naming

The database column names are **misleading**:
- `week_start_date` - Sounds like "start of the week" but it's NOT
- `week_end_date` - Sounds like "end of the week" but it's NOT

## What They Actually Mean

### `week_start_date` Column
**Actually stores:** When the commitment **started** (when the user clicked "Commit")
- This is `current_date` when the user commits
- Different users commit on different days
- **NOT** the start of a calendar week

### `week_end_date` Column  
**Actually stores:** The **deadline** (next Monday before noon)
- This is the same for all users who commit in the same week
- All commitments that end on the same Monday belong to the same "week"
- **This is what groups commitments by week**

---

## Example Scenario

Let's say today is **Wednesday, Nov 13, 2024**:

### User A commits on Wednesday, Nov 13:
- `week_start_date` = `2024-11-13` (when they committed)
- `week_end_date` = `2024-11-18` (next Monday - deadline)

### User B commits on Friday, Nov 15:
- `week_start_date` = `2024-11-15` (when they committed) 
- `week_end_date` = `2024-11-18` (same Monday - same deadline)

### User C commits on Sunday, Nov 17:
- `week_start_date` = `2024-11-17` (when they committed)
- `week_end_date` = `2024-11-18` (same Monday - same deadline)

---

## The Problem

**To find "all commitments for this week", you need to match by `week_end_date` (deadline), NOT `week_start_date`!**

### ❌ WRONG (what weekly-close currently does):
```typescript
// This finds commitments that STARTED on a specific date
.eq("week_start_date", "2024-11-13")
```
**Problem:** This only finds User A, not User B or C (even though they're in the same week!)

### ✅ CORRECT (what it should do):
```typescript
// This finds commitments that END on the same deadline
.eq("week_end_date", "2024-11-18")
```
**Result:** Finds User A, B, and C (all commitments ending on Monday Nov 18)

---

## Why This Matters for weekly-close

When closing "last week", you need to:
1. Find all commitments that ended on the same Monday (same deadline)
2. Sum up their penalties
3. Charge all those users

**Current bug:** The function uses `week_start_date` to find commitments, so it might:
- Miss some users who committed later in the week
- Include users from different weeks who happened to commit on the same day

**Fix:** Use `week_end_date` (deadline) to identify which week to close.

---

## Visual Example

```
Week ending Monday Nov 18 (deadline = 2024-11-18):
├── User A: week_start_date = 2024-11-13, week_end_date = 2024-11-18 ✅
├── User B: week_start_date = 2024-11-15, week_end_date = 2024-11-18 ✅
└── User C: week_start_date = 2024-11-17, week_end_date = 2024-11-18 ✅

To find all users in this week:
✅ .eq("week_end_date", "2024-11-18")  → Finds A, B, C
❌ .eq("week_start_date", "2024-11-13") → Only finds A
```

---

## Summary

- **`week_start_date`** = When user committed (varies per user)
- **`week_end_date`** = Deadline (same for all users in same week)
- **To group by week:** Use `week_end_date` (deadline)
- **weekly-close bug:** Currently uses `week_start_date` instead of `week_end_date`


