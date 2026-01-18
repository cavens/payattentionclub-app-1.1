# Billing Status "User Not Found" Error - Analysis

**Date**: 2026-01-15  
**Issue**: `billing-status` Edge Function returns "User row not found in public.users" error

---

## Problem

When trying to check billing status (Step 1 of lock-in flow), the Edge Function returns:
```
{"error":"User row not found in public.users"}
```

**Error occurs at**: Line 93-99 in `billing-status/index.ts`

---

## Code Flow Analysis

### Current Flow in `billing-status/index.ts`

1. **Line 74**: Get authenticated user from JWT
   ```typescript
   const { data: { user }, error: userError } = await supabase.auth.getUser();
   ```
   ✅ This succeeds (user is authenticated)

2. **Line 83**: Extract `userId` from auth user
   ```typescript
   const userId = user.id;  // ⚠️ MISSING in current code!
   ```

3. **Line 87-90**: Query `public.users` table
   ```typescript
   const { data: dbUser, error: dbUserError } = await supabase
     .from("users")
     .select("id, email, stripe_customer_id, has_active_payment_method")
     .eq("id", userId)  // ⚠️ userId might be undefined!
     .single();
   ```

4. **Line 93-99**: If query fails, return error
   ```typescript
   if (dbUserError) {
     return new Response(JSON.stringify({
       error: "User row not found in public.users"
     }), { status: 400 });
   }
   ```

---

## Root Cause Analysis

### Issue 1: Missing `userId` Variable Declaration

**Location**: Line 83 in `billing-status/index.ts`

**Problem**: The code uses `userId` on line 90, but `userId` is not declared. Looking at the code snippet, I see:
- Line 74: `const { data: { user }, error: userError } = await supabase.auth.getUser();`
- Line 84: `const userEmail = user.email ?? undefined;`
- Line 90: `.eq("id", userId)` ← **userId is not defined!**

**Impact**: If `userId` is undefined, the query `.eq("id", undefined)` will fail to find any rows, resulting in the "User row not found" error.

---

### Issue 2: User Row Not Created in `public.users` Table

**Alternative Root Cause**: Even if `userId` is correctly defined, the user might not exist in the `public.users` table.

**Why this could happen**:
1. **No database trigger**: When a user signs up via Supabase Auth, a row might not be automatically created in `public.users`
2. **Manual user creation**: Users might be created in `auth.users` but not in `public.users`
3. **Migration issue**: The `public.users` table might not have been populated for existing users

**Evidence**:
- Preview max charge works (user is authenticated)
- Billing status fails (user not found in `public.users`)
- This suggests the user exists in `auth.users` but not in `public.users`

---

## Verification Steps

### Step 1: Check if `userId` is defined

**Check the actual code**:
```typescript
// After line 74
const userId = user.id;  // Is this line present?
```

**If missing**: Add it before line 87.

---

### Step 2: Check if user exists in `public.users`

**Query the database**:
```sql
SELECT id, email, created_at 
FROM public.users 
WHERE id = '<user_id_from_auth>';
```

**If no rows returned**: User doesn't exist in `public.users` table.

---

### Step 3: Check for database trigger

**Check if there's a trigger that creates user rows**:
```sql
SELECT * 
FROM pg_trigger 
WHERE tgname LIKE '%user%' OR tgname LIKE '%auth%';
```

**Or check for a function**:
```sql
SELECT * 
FROM information_schema.routines 
WHERE routine_name LIKE '%user%' OR routine_name LIKE '%auth%';
```

---

## Solutions

### Solution 1: Fix Missing `userId` Variable (If Missing)

**Add after line 74**:
```typescript
const userId = user.id;
```

**Then use it on line 90**:
```typescript
.eq("id", userId)
```

---

### Solution 2: Create User Row if Missing (Recommended)

**Modify `billing-status/index.ts`** to create user row if it doesn't exist:

```typescript
// After getting user from auth
const userId = user.id;
const userEmail = user.email ?? undefined;

// Try to fetch user row from public.users
let { data: dbUser, error: dbUserError } = await supabase
  .from("users")
  .select("id, email, stripe_customer_id, has_active_payment_method")
  .eq("id", userId)
  .single();

// If user doesn't exist, create it
if (dbUserError && dbUserError.code === 'PGRST116') {  // PGRST116 = no rows returned
  console.log("billing-status: User not found in public.users, creating row...");
  
  const { data: newUser, error: createError } = await supabase
    .from("users")
    .insert({
      id: userId,
      email: userEmail,
      stripe_customer_id: null,
      has_active_payment_method: false
    })
    .select()
    .single();
  
  if (createError) {
    console.error("billing-status: Error creating user row:", createError);
    return new Response(JSON.stringify({
      error: "Failed to create user row",
      details: createError.message
    }), { status: 500 });
  }
  
  dbUser = newUser;
  console.log("billing-status: ✅ User row created successfully");
} else if (dbUserError) {
  // Other error (not "not found")
  console.error("billing-status: Error fetching user row:", dbUserError);
  return new Response(JSON.stringify({
    error: "User row not found in public.users",
    details: dbUserError.message
  }), { status: 400 });
}
```

**Benefits**:
- Automatically creates user row if missing
- Handles the case where user exists in auth but not in public.users
- More robust error handling

---

### Solution 3: Create Database Trigger (Long-term)

**Create a trigger** that automatically creates a row in `public.users` when a user signs up:

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, created_at)
  VALUES (NEW.id, NEW.email, NOW())
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
```

**Benefits**:
- Automatic user creation
- Prevents this issue for future users
- Single source of truth

---

## Recommended Approach

### Immediate Fix (Solution 2)

**Implement Solution 2** (create user row if missing) because:
1. ✅ Fixes the immediate issue
2. ✅ Handles existing users who don't have rows
3. ✅ No database migration needed
4. ✅ Works for both new and existing users

### Long-term Fix (Solution 3)

**Implement Solution 3** (database trigger) because:
1. ✅ Prevents this issue for future users
2. ✅ Ensures consistency
3. ✅ Reduces code complexity

---

## Testing

### Test 1: Verify `userId` is defined

**Check logs**:
- Look for any "userId is undefined" errors
- Check if the query is using the correct user ID

### Test 2: Verify user row creation

**After implementing Solution 2**:
1. Try to check billing status
2. Check database: `SELECT * FROM public.users WHERE id = '<user_id>';`
3. Verify user row was created

### Test 3: Verify trigger (if implemented)

**After implementing Solution 3**:
1. Create a new test user
2. Check database: `SELECT * FROM public.users WHERE id = '<new_user_id>';`
3. Verify user row was automatically created

---

## Conclusion

**Most Likely Issue**: User exists in `auth.users` but not in `public.users` table.

**Recommended Fix**: 
1. **Immediate**: Implement Solution 2 (create user row if missing in Edge Function)
2. **Long-term**: Implement Solution 3 (database trigger for automatic user creation)

**Priority**: High - This prevents users from completing the lock-in flow.



