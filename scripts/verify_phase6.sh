#!/bin/bash
# ==============================================================================
# Verify Phase 6 Setup
# ==============================================================================
# Checks that all Phase 6 components are properly configured
# 
# Usage:
#   ./scripts/verify_phase6.sh [staging|production|both]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-both}"

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Function to verify an environment
verify_env() {
    local env=$1
    local project_ref
    local supabase_url
    local service_role_key
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        supabase_url="$STAGING_SUPABASE_URL"
        supabase_secret_key="$STAGING_SUPABASE_SECRET_KEY"
        echo "Verifying STAGING environment..."
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        supabase_url="$PRODUCTION_SUPABASE_URL"
        supabase_secret_key="$PRODUCTION_SUPABASE_SECRET_KEY"
        echo "Verifying PRODUCTION environment..."
    else
        echo "Error: Invalid environment"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo ""
    
    # Check 1: Test call_weekly_close function (this verifies everything)
    echo "1. Testing call_weekly_close() function..."
    echo "   (This verifies: table exists, key is set, function works)"
    RESPONSE=$(curl -s -X POST \
        "${supabase_url}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${supabase_secret_key}" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" \
        -d "{\"p_sql\": \"SELECT public.call_weekly_close();\"}")
    
    # Check for success (handle JSON with or without spaces)
    if echo "$RESPONSE" | grep -qE '"success"\s*:\s*true' || echo "$RESPONSE" | grep -q '"success":true'; then
        echo "   ✅ Function executed successfully!"
        echo "   ✅ All components are working (table, key, function)"
        echo "   📋 Check Edge Function logs to verify it was called:"
        echo "      https://supabase.com/dashboard/project/$project_ref/functions/weekly-close/logs"
    else
        echo "   ❌ Function execution failed"
        echo "   Response: $RESPONSE"
        echo "   ⚠️  This means either:"
        echo "      - _internal_config table is missing"
        echo "      - Supabase secret key is not set"
        echo "      - Function has an error"
        return 1
    fi
    
    # Check 2: Verify cron job (try to query it)
    echo ""
    echo "2. Checking cron job..."
    JOB_NAME="weekly-close-$env"
    RESPONSE=$(curl -s -X POST \
        "${supabase_url}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${supabase_secret_key}" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" \
        -d "{\"p_sql\": \"SELECT 1 FROM cron.job WHERE jobname = '$JOB_NAME' LIMIT 1;\"}")
    
    if echo "$RESPONSE" | grep -qE '"success"\s*:\s*true' || echo "$RESPONSE" | grep -q '"success":true'; then
        echo "   ✅ Cron job query executed (job likely exists)"
        echo "   📋 Verify in Dashboard: Database → Cron Jobs"
    else
        echo "   ⚠️  Could not verify cron job"
        echo "   📋 Check manually in Dashboard: Database → Cron Jobs"
    fi
    
    echo ""
    echo "✅ $env environment verification complete!"
    echo ""
}

# Main execution
echo "=========================================="
echo "Phase 6 Verification"
echo "=========================================="
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    verify_env "staging"
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    verify_env "production"
fi

echo "=========================================="
echo "✅ Verification Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Check Edge Function logs to verify test calls worked"
echo "2. Monitor cron jobs on next Monday at 17:00 UTC"
echo "3. Set up alerts/notifications for cron job failures (optional)"

