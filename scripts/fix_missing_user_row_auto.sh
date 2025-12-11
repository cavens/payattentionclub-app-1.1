#!/bin/bash
# ==============================================================================
# Automatically Fix Missing User Rows
# ==============================================================================
# Creates missing user rows in public.users for users that exist in auth.users
# Works via REST API (no psql connection needed)
# 
# Usage:
#   ./scripts/fix_missing_user_row_auto.sh [staging|production|both]
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

# SQL query to fix missing user rows
FIX_SQL="INSERT INTO public.users (id, email, created_at)
SELECT 
    au.id,
    au.email,
    au.created_at
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
WHERE pu.id IS NULL
ON CONFLICT (id) DO NOTHING;"

# Function to fix for an environment
fix_env() {
    local env=$1
    
    echo "=========================================="
    echo "Fixing missing user rows in $env"
    echo "=========================================="
    echo ""
    
    # First, deploy the RPC function if it doesn't exist
    echo "Step 1: Checking if rpc_execute_sql function exists..."
    
    if [ "$env" = "staging" ]; then
        SUPABASE_URL="$STAGING_SUPABASE_URL"
        SERVICE_ROLE_KEY="$STAGING_SUPABASE_SERVICE_ROLE_KEY"
    else
        SUPABASE_URL="$PRODUCTION_SUPABASE_URL"
        SERVICE_ROLE_KEY="$PRODUCTION_SUPABASE_SERVICE_ROLE_KEY"
    fi
    
    # Check if function exists by trying to call it
    CHECK_RESPONSE=$(curl -s -X POST \
        "${SUPABASE_URL}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${SERVICE_ROLE_KEY}" \
        -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"p_sql": "SELECT 1;"}' 2>&1)
    
    if echo "$CHECK_RESPONSE" | grep -q "Could not find the function"; then
        echo "⚠️  rpc_execute_sql function not found."
        echo "   Deploy it first: supabase/remote_rpcs/rpc_execute_sql.sql"
        echo "   Or use SQL Editor to run the fix manually."
        return 1
    fi
    
    echo "✅ Function exists. Executing fix..."
    echo ""
    
    # Execute the fix SQL
    RESPONSE=$(curl -s -X POST \
        "${SUPABASE_URL}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${SERVICE_ROLE_KEY}" \
        -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"p_sql\": $(echo "$FIX_SQL" | jq -Rs . 2>/dev/null || echo "\"$FIX_SQL\"")}")
    
    if command -v jq >/dev/null 2>&1; then
        echo "$RESPONSE" | jq .
    else
        echo "$RESPONSE"
    fi
    
    # Check for success (handle both with and without spaces in JSON)
    if echo "$RESPONSE" | grep -q '"success" *: *true' || echo "$RESPONSE" | grep -q '"success":true'; then
        echo ""
        echo "✅ Missing user rows created!"
    else
        echo ""
        echo "❌ Failed to execute SQL"
        echo "   Response: $RESPONSE"
        return 1
    fi
    
    echo ""
}

# Main execution
if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    fix_env "staging"
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    if [ "$ENVIRONMENT" = "production" ]; then
        echo "⚠️  WARNING: About to modify production database!"
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    fix_env "production"
fi

echo "=========================================="
echo "✅ Complete!"
echo "=========================================="

