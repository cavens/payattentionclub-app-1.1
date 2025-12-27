# Testing Steps 1-2: Commitment ID Storage

## What We're Testing
- Step 1: Commitment ID storage methods in UsageTracker
- Step 2: Storing commitment ID when commitment is created

## Test Steps

### 1. Build and Run
- Build the app on a physical device (or simulator)
- Make sure you're signed in

### 2. Create a Commitment
1. Go through the setup flow:
   - Set a limit (e.g., 30 minutes)
   - Set a penalty (e.g., $0.10/min)
   - Select apps to monitor
2. Click "Lock in the money"
3. Complete the payment setup (if needed)

### 3. Check Logs

#### In Xcode Console:
- Look for these log messages:

**Expected Logs:**
```
LOCKIN AuthorizationView: ✅ Step 2 complete - Commitment created successfully!
LOCKIN AuthorizationView: commitmentId: [some-uuid]
EXTENSION UsageTracker: ✅ Stored commitment ID: [same-uuid]
```

**If you see:**
- ✅ `EXTENSION UsageTracker: ✅ Stored commitment ID: [uuid]` → **SUCCESS!** Steps 1-2 are working
- ❌ No "Stored commitment ID" message → Something went wrong

### 4. Verify App Group Storage (Optional)

You can verify the commitment ID is actually stored in App Group by:

**Option A: Add a test button** (temporary, for testing)
- Add a button that calls `UsageTracker.shared.getCommitmentId()` and prints it
- Should show the same UUID that was stored

**Option B: Check via code**
- The commitment ID should be accessible via:
  ```swift
  let id = UsageTracker.shared.getCommitmentId()
  print("Stored commitment ID: \(id ?? "nil")")
  ```

### 5. Test Clearing (Optional)

To test that clearing works:
- Wait for deadline to pass OR
- Manually call `UsageTracker.shared.clearCommitmentId()`
- Verify commitment ID is cleared

## Success Criteria

✅ **Step 1-2 Test Passes If:**
- Commitment ID is logged when stored
- Commitment ID can be retrieved via `getCommitmentId()`
- Commitment ID is cleared when monitoring expires

## Troubleshooting

### No "Stored commitment ID" log?
- Check that commitment was actually created (look for "Step 2 complete" log)
- Check that `UsageTracker.shared.storeCommitmentId()` is being called
- Verify App Group is accessible (check for other App Group logs)

### Commitment ID is nil when retrieved?
- Make sure you're calling `getCommitmentId()` AFTER creating the commitment
- Check that App Group identifier matches: `group.com.payattentionclub2.0.app`

## Next Steps After Testing

If test passes:
- ✅ Proceed with Step 3 (Store auth token in App Group)

If test fails:
- Check logs for errors
- Verify App Group configuration
- Check that commitment was actually created








