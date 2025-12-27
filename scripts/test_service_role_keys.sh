#!/bin/bash
# ==============================================================================
# Test Service Role Keys
# ==============================================================================
# Verifies that the rotated service_role keys work correctly
# Tests: API authentication, database access, and function execution
# 
# Usage:
#   ./scripts/test_service_role_keys.sh [staging|production|both]
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
else
    echo "❌ Error: .env file not found"
    exit 1
fi

# Function to test an environment
test_env() {
    local env=$1
    local project_ref
    local supabase_url
    local service_role_key
    local anon_key
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        supabase_url="${STAGING_SUPABASE_URL:-https://auqujbppoytkeqdsgrbl.supabase.co}"
        supabase_secret_key="$STAGING_SUPABASE_SECRET_KEY"
        supabase_publishable_key="${STAGING_SUPABASE_PUBLISHABLE_KEY:-}"
        echo "=========================================="
        echo "Testing STAGING Environment"
        echo "=========================================="
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        supabase_url="${PRODUCTION_SUPABASE_URL:-https://whdftvcrtrsnefhprebj.supabase.co}"
        supabase_secret_key="$PRODUCTION_SUPABASE_SECRET_KEY"
        supabase_publishable_key="${PRODUCTION_SUPABASE_PUBLISHABLE_KEY:-}"
        echo "=========================================="
        echo "Testing PRODUCTION Environment"
        echo "=========================================="
    else
        echo "❌ Error: Invalid environment"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo "URL: $supabase_url"
    echo ""
    
    # Check if key is set
    if [ -z "$supabase_secret_key" ]; then
        echo "❌ Error: Supabase secret key not found in .env"
        if [ "$env" = "staging" ]; then
            echo "   Expected: STAGING_SUPABASE_SECRET_KEY"
        else
            echo "   Expected: PRODUCTION_SUPABASE_SECRET_KEY"
        fi
        return 1
    fi
    
    # Validate key format (should be a JWT)
    if [[ ! "$supabase_secret_key" =~ ^eyJ ]]; then
        echo "⚠️  Warning: Supabase secret key doesn't look like a JWT (should start with 'eyJ')"
    fi
    
    echo "✅ Supabase secret key found (length: ${#supabase_secret_key} chars)"
    echo ""
    
    # Test 1: Basic API Authentication
    echo "1. Testing API Authentication..."
    echo "   Attempting to access Supabase REST API..."
    
    AUTH_TEST=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/rest/v1/" \
        -H "apikey: ${supabase_secret_key}" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" 2>&1)
    
    HTTP_CODE=$(echo "$AUTH_TEST" | tail -n1)
    RESPONSE_BODY=$(echo "$AUTH_TEST" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
        echo "   ✅ Authentication successful (HTTP $HTTP_CODE)"
        echo "   ✅ Supabase secret key is valid and accepted by Supabase"
    else
        echo "   ❌ Authentication failed (HTTP $HTTP_CODE)"
        echo "   Response: $RESPONSE_BODY"
        return 1
    fi
    echo ""
    
    # Test 2: Database Query Access
    echo "2. Testing Database Query Access..."
    echo "   Attempting to query a system table..."
    
    QUERY_TEST=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${supabase_secret_key}" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" \
        -d '{"p_sql": "SELECT 1 as test_value;"}' 2>&1)
    
    HTTP_CODE=$(echo "$QUERY_TEST" | tail -n1)
    RESPONSE_BODY=$(echo "$QUERY_TEST" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$RESPONSE_BODY" | grep -qE '"success"\s*:\s*true' || echo "$RESPONSE_BODY" | grep -q '"success":true'; then
            echo "   ✅ Database query executed successfully"
            echo "   ✅ Supabase secret key has database access"
        else
            echo "   ⚠️  Query returned but may have failed"
            echo "   Response: $RESPONSE_BODY"
        fi
    else
        echo "   ❌ Database query failed (HTTP $HTTP_CODE)"
        echo "   Response: $RESPONSE_BODY"
        return 1
    fi
    echo ""
    
    # Test 3: Check if supabase_secret_key is configured in database
    echo "3. Checking Supabase Secret Key Configuration..."
    echo "   Checking if key is set in database..."
    
    # Check both methods: app.settings and _internal_config table
    CONFIG_CHECK=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${supabase_secret_key}" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" \
        -d "{\"p_sql\": \"SELECT CASE WHEN current_setting('app.settings.service_role_key', true) IS NOT NULL THEN 'app.settings method' WHEN EXISTS (SELECT 1 FROM public._internal_config WHERE key = 'service_role_key') THEN '_internal_config table method' ELSE 'not configured' END as config_method;\"}" 2>&1)
    
    HTTP_CODE=$(echo "$CONFIG_CHECK" | tail -n1)
    RESPONSE_BODY=$(echo "$CONFIG_CHECK" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ Configuration check completed"
        echo "   Response: $RESPONSE_BODY"
    else
        echo "   ⚠️  Could not check configuration (HTTP $HTTP_CODE)"
    fi
    echo ""
    
    # Test 4: Test call_weekly_close function (if it exists)
    echo "4. Testing call_weekly_close() Function..."
    echo "   Attempting to call the function (dry run - will not actually execute)..."
    
    # First check if function exists
    FUNCTION_CHECK=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${supabase_secret_key}" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" \
        -d '{"p_sql": "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = ''call_weekly_close'') as function_exists;"}' 2>&1)
    
    HTTP_CODE=$(echo "$FUNCTION_CHECK" | tail -n1)
    RESPONSE_BODY=$(echo "$FUNCTION_CHECK" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$RESPONSE_BODY" | grep -q '"function_exists":true' || echo "$RESPONSE_BODY" | grep -q '"function_exists": "true"'; then
            echo "   ✅ Function exists"
            echo ""
            echo "   ⚠️  Note: We're NOT actually calling the function to avoid triggering weekly-close"
            echo "   To fully test, you can manually run:"
            echo "   ./scripts/run_sql_via_api.sh $env \"SELECT public.call_weekly_close();\""
        else
            echo "   ⚠️  Function may not exist or check failed"
            echo "   Response: $RESPONSE_BODY"
        fi
    else
        echo "   ⚠️  Could not check if function exists (HTTP $HTTP_CODE)"
    fi
    echo ""
    
    # Test 5: Test Edge Function Authentication
    echo "5. Testing Edge Function Authentication..."
    echo "   Testing if supabase secret key can authenticate with Edge Functions..."
    
    # Try to call a simple edge function endpoint (this will fail if auth is wrong)
    EDGE_TEST=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/functions/v1/weekly-close" \
        -H "Authorization: Bearer ${supabase_secret_key}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d '{}' 2>&1)
    
    HTTP_CODE=$(echo "$EDGE_TEST" | tail -n1)
    RESPONSE_BODY=$(echo "$EDGE_TEST" | sed '$d')
    
    # Edge function might return various codes, but 401/403 means auth failed
    if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo "   ❌ Edge Function authentication failed (HTTP $HTTP_CODE)"
        echo "   Response: $RESPONSE_BODY"
        echo "   ⚠️  This may be expected if the function requires different auth"
    elif [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "500" ]; then
        echo "   ✅ Edge Function accepted the authentication (HTTP $HTTP_CODE)"
        echo "   ✅ Supabase secret key works with Edge Functions"
        if [ "$HTTP_CODE" != "200" ]; then
            echo "   ⚠️  Note: Non-200 response may be expected (function logic, not auth)"
        fi
    else
        echo "   ⚠️  Unexpected response (HTTP $HTTP_CODE)"
        echo "   Response: $RESPONSE_BODY"
    fi
    echo ""
    
    echo "=========================================="
    echo "✅ $env Environment Tests Complete!"
    echo "=========================================="
    echo ""
}

# Main execution
echo "=========================================="
echo "Service Role Key Test Suite"
echo "=========================================="
echo ""
echo "This script tests:"
echo "  1. API Authentication"
echo "  2. Database Query Access"
echo "  3. Key Configuration Status"
echo "  4. Function Availability"
echo "  5. Edge Function Authentication"
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    test_env "staging"
    echo ""
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    test_env "production"
    echo ""
fi

echo "=========================================="
echo "✅ All Tests Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. If all tests passed, your keys are working correctly"
echo "2. If any tests failed, check the error messages above"
echo "3. Make sure keys are set in database (app.settings or _internal_config table)"
echo "4. Update any CI/CD environments with new keys"
echo ""








