# Authorization Fee Calculation Fix

## Problem
The authorization amount displayed before committing was way too high (e.g., $675 for a 4-day period). The calculation assumed users could use monitored apps 24/7, which is unrealistic.

## Solution
Implemented a **single source of truth** in the backend:

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│   calculate_max_charge_cents()                      │
│   (Internal SQL function - THE formula)             │
│                                                     │
└──────────────┬──────────────────────┬───────────────┘
               │                      │
               ▼                      ▼
┌──────────────────────┐   ┌──────────────────────┐
│ rpc_preview_max_charge│   │ rpc_create_commitment │
│ (Frontend preview)    │   │ (Stores the value)    │
└──────────────────────┘   └──────────────────────┘
```

## New Formula
Located in `supabase/remote_rpcs/calculate_max_charge_cents.sql`:

- **Realistic daily usage cap**: Assumes max ~10 hours/day usage, not 24
- **Risk factor**: 1.0 base + 0.05 per app (capped at 2.0)
- **Bounds**: Minimum $5, Maximum $1000
- **Scale**: Based on days remaining (capped at 7 days)

## Files Changed

### Backend (SQL)
- `supabase/remote_rpcs/calculate_max_charge_cents.sql` - NEW: The formula
- `supabase/remote_rpcs/rpc_preview_max_charge.sql` - NEW: Frontend preview
- `supabase/remote_rpcs/rpc_create_commitment.sql` - UPDATED: Uses shared formula

### Frontend (Swift)
- `Utilities/BackendClient.swift` - Added `previewMaxCharge()` method
- `Models/AppModel.swift` - Changed `calculateAuthorizationAmount()` to `fetchAuthorizationAmount()` (async, calls backend)
- `Views/AuthorizationView.swift` - Uses `.task{}` to fetch from backend
- `Utilities/PenaltyCalculator.swift` - Deprecated `calculateAuthorizationAmount()` (kept for tests only)

## Deployment Steps

### 1. Deploy SQL Functions (in order)
Run these in Supabase SQL Editor for **both staging and production**:

```sql
-- First: create the internal calculation function
-- Copy contents of: supabase/remote_rpcs/calculate_max_charge_cents.sql

-- Second: create the preview RPC
-- Copy contents of: supabase/remote_rpcs/rpc_preview_max_charge.sql

-- Third: update the create commitment RPC
-- Copy contents of: supabase/remote_rpcs/rpc_create_commitment.sql
```

### 2. Test the Preview RPC
```sql
-- Test with typical values
SELECT * FROM rpc_preview_max_charge(
    '2024-12-16'::date,  -- Next Monday
    1260,                 -- 21 hours (1260 minutes)
    10,                   -- $0.10/min penalty
    '{"app_bundle_ids": [], "categories": []}'::jsonb
);
```

Expected: `max_charge_cents` between 500 and 100000 (i.e., $5-$1000)

### 3. Build and Test iOS App
1. Open Xcode
2. Build and run on device/simulator
3. Go through setup flow to Authorization screen
4. Verify amount shows a loading spinner briefly, then a reasonable value ($5-$100)

## Verification

### Backend
```sql
-- Verify functions exist
SELECT proname FROM pg_proc WHERE proname IN (
    'calculate_max_charge_cents',
    'rpc_preview_max_charge',
    'rpc_create_commitment'
);
```

### Frontend
- Authorization amount should show loading spinner briefly
- Amount should be between $5.00 and $100.00
- Amount should match what gets stored when you commit

## Rollback
If needed, the old `rpc_create_commitment.sql` calculation can be restored:
```sql
-- Old formula (DO NOT USE - leads to crazy high amounts):
v_potential_overage := greatest(0, v_minutes_remaining - p_limit_minutes);
v_max_charge_cents := v_potential_overage * p_penalty_per_minute_cents * v_risk_factor;
```
