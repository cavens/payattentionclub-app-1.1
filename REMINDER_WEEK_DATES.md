# ✅ Week Start/End Date Issue - RESOLVED

## Issue (Resolved)
The `week_start_date` and `week_end_date` fields in the `commitments` table had confusing naming.

## Solution Implemented
**Kept database column names** (to avoid breaking changes) but **clarified naming in code**:

### Database Columns (Legacy Naming - Kept)
- `week_start_date`: Actually stores when the commitment started (current_date, when user commits)
- `week_end_date`: Actually stores the deadline (next Monday before noon)

### Code Updates
1. **SQL Function:**
   - Parameter renamed: `p_week_start_date` → `p_deadline_date` ✅
   - Added clear comments explaining legacy column naming ✅
   - Logic correctly sets:
     - `week_start_date` = `current_date` (when user commits)
     - `week_end_date` = `p_deadline_date` (deadline, next Monday)

2. **Swift Code:**
   - `CommitmentResponse` properties renamed: `weekStartDate` → `startDate`, `weekEndDate` → `deadlineDate` ✅
   - Added documentation comments explaining the mapping ✅
   - Function parameter documentation updated to clarify it's the deadline ✅

3. **Edge Function:**
   - Updated to use `p_deadline_date` parameter ✅
   - Added comments explaining the deadline vs start date ✅

## Files Changed
- ✅ `rpc_create_commitment_updated.sql` - Clearer parameter naming and comments
- ✅ `create-commitment-edge-function.ts` - Updated parameter mapping
- ✅ `BackendClient.swift` - Renamed response properties, updated documentation

## Status
✅ **RESOLVED** - Naming is now clear in code, database columns kept for compatibility

## Future Consideration (Optional)
If we want to rename database columns in the future, we would need:
- Database migration script
- Update all queries/references
- Update `weekly_pools` table if needed
But this is not necessary - the current solution with clear documentation works well.

---
Created: Yesterday
Status: ✅ Resolved

