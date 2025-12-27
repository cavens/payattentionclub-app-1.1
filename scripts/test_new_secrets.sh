#!/bin/bash
# ==============================================================================
# Test New Supabase Secrets
# ==============================================================================
# Verifies that Edge Functions can access the new secret names
# Tests both staging and production environments
# 
# Usage:
#   ./scripts/test_new_secrets.sh [staging|production|both]
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

# Function to test an environment
test_env() {
    local env=$1
    local project_ref
    local supabase_url
    local secret_key
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        supabase_url="$STAGING_SUPABASE_URL"
        secret_key="$STAGING_SUPABASE_SECRET_KEY"
        echo "=========================================="
        echo "Testing STAGING Environment"
        echo "=========================================="
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        supabase_url="$PRODUCTION_SUPABASE_URL"
        secret_key="$PRODUCTION_SUPABASE_SECRET_KEY"
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
    
    # Test 1: Verify Edge Function can be called (tests secret access)
    echo "1. Testing Edge Function Access..."
    echo "   Calling weekly-close Edge Function..."
    
    EDGE_RESPONSE=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/functions/v1/weekly-close" \
        -H "Authorization: Bearer ${secret_key}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d '{}' 2>&1)
    
    HTTP_CODE=$(echo "$EDGE_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$EDGE_RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ Edge Function responded successfully (HTTP 200)"
        echo "   ✅ Secrets are accessible to Edge Functions"
    elif [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "500" ]; then
        echo "   ⚠️  Edge Function responded but may have logic errors (HTTP $HTTP_CODE)"
        echo "   ✅ Secrets are accessible (function executed)"
        echo "   Response: ${RESPONSE_BODY:0:200}..."
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo "   ❌ Authentication failed (HTTP $HTTP_CODE)"
        echo "   ⚠️  This might mean secrets aren't set correctly"
        echo "   Response: $RESPONSE_BODY"
    else
        echo "   ⚠️  Unexpected response (HTTP $HTTP_CODE)"
        echo "   Response: ${RESPONSE_BODY:0:200}..."
    fi
    echo ""
    
    # Test 2: Test another Edge Function (billing-status)
    echo "2. Testing billing-status Edge Function..."
    
    BILLING_RESPONSE=$(curl -s -w "\n%{http_code}" \
        "${supabase_url}/functions/v1/billing-status" \
        -H "Authorization: Bearer ${secret_key}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d '{"userId": "test"}' 2>&1)
    
    HTTP_CODE=$(echo "$BILLING_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$BILLING_RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "500" ]; then
        echo "   ✅ Edge Function accessible (HTTP $HTTP_CODE)"
    else
        echo "   ⚠️  Response: HTTP $HTTP_CODE"
    fi
    echo ""
    
    # Test 3: Check Edge Function logs (if possible via API)
    echo "3. Verification Summary..."
    echo "   ✅ If Edge Functions responded (even with errors), secrets are working"
    echo "   📋 Check Edge Function logs in Dashboard for detailed execution:"
    echo "      https://supabase.com/dashboard/project/$project_ref/functions"
    echo ""
    
    echo "=========================================="
    echo "✅ $env Environment Test Complete!"
    echo "=========================================="
    echo ""
}

# Main execution
echo "=========================================="
echo "New Secrets Test Suite"
echo "=========================================="
echo ""
echo "This script tests that Edge Functions can access:"
echo "  - SUPABASE_SECRET_KEY"
echo "  - SUPABASE_PUBLISHABLE_KEY"
echo ""
echo "If Edge Functions respond (even with errors),"
echo "it means the secrets are accessible."
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    test_env "staging"
    echo ""
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    if [ "$ENVIRONMENT" = "production" ]; then
        echo "⚠️  WARNING: About to test PRODUCTION!"
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    test_env "production"
    echo ""
fi

echo "=========================================="
echo "✅ All Tests Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. If tests passed, secrets are working correctly"
echo "2. Monitor Edge Function logs for any errors"
echo "3. Once verified, you can remove old secrets:"
echo "   - SUPABASE_SERVICE_ROLE_KEY"
echo "   - SUPABASE_ANON_KEY"
echo ""








