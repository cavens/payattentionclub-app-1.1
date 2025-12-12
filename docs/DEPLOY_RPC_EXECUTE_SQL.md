# Deploy rpc_execute_sql Function

## One-Time Manual Deployment

Yes, you need to deploy the `rpc_execute_sql` function **manually once** in each environment. After that, all SQL execution can be automated!

## Quick Deployment Steps

### Staging

1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/sql/new
2. Open: `supabase/remote_rpcs/rpc_execute_sql.sql`
3. Copy the entire contents
4. Paste into SQL Editor
5. Click **"Run"**

### Production

1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/sql/new
2. Open: `supabase/remote_rpcs/rpc_execute_sql.sql`
3. Copy the entire contents
4. Paste into SQL Editor
5. Click **"Run"**

## Verify Deployment

After deploying, verify it works:

```bash
# Test in staging
./scripts/run_sql_via_api.sh staging "SELECT 1 as test;"

# Test in production
./scripts/run_sql_via_api.sh production "SELECT 1 as test;"
```

You should see:
```json
{
  "success": true,
  "message": "SQL executed successfully"
}
```

## Why Manual Deployment?

The `rpc_execute_sql` function needs to exist before we can use it to execute SQL via REST API. It's a "bootstrap" function that enables automation.

Once deployed, you can:
- ✅ Run SQL automatically via scripts
- ✅ Fix missing user rows automatically
- ✅ Execute any SQL without manual SQL Editor steps

## Security Note

The `rpc_execute_sql` function is restricted to `service_role` only. Regular users cannot execute arbitrary SQL. This is safe for automation scripts that use the service role key.

## Alternative: Use Existing Deploy Script

You can also use the existing deploy script, which will show you all RPC functions to deploy:

```bash
./scripts/deploy_rpc_functions.sh staging
./scripts/deploy_rpc_functions.sh production
```

This will list all RPC functions including `rpc_execute_sql.sql` that need to be deployed.


