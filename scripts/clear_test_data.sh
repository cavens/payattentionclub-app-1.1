#!/bin/bash
# ==============================================================================
# Clear Test Data from Supabase
# ==============================================================================
# Lists users and optionally clears test data from staging/production
# 
# Usage:
#   ./scripts/clear_test_data.sh [staging|production|both] [list|clear]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-both}"
ACTION="${2:-list}"

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Function to list/clear users for an environment
process_env() {
    local env=$1
    local project_ref
    local db_url
    local service_role_key
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        db_url="$STAGING_DB_URL"
        service_role_key="$STAGING_SUPABASE_SERVICE_ROLE_KEY"
        supabase_url="$STAGING_SUPABASE_URL"
        echo "Processing STAGING environment..."
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        db_url="$PRODUCTION_DB_URL"
        service_role_key="$PRODUCTION_SUPABASE_SERVICE_ROLE_KEY"
        supabase_url="$PRODUCTION_SUPABASE_URL"
        echo "Processing PRODUCTION environment..."
    else
        echo "Error: Invalid environment: $env"
        return 1
    fi
    
    if [ -z "$supabase_url" ] || [ -z "$service_role_key" ]; then
        echo "❌ Error: Missing environment variables for $env"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo ""
    
    if [ "$ACTION" = "list" ]; then
        echo "📋 Listing users in $env..."
        echo ""
        
        # List users via API
        curl -s -X GET \
            "${supabase_url}/rest/v1/users?select=id,email,created_at" \
            -H "apikey: ${service_role_key}" \
            -H "Authorization: Bearer ${service_role_key}" \
            -H "Content-Type: application/json" | \
            deno eval "
                const data = JSON.parse(await Deno.stdin.readText());
                if (Array.isArray(data) && data.length > 0) {
                    console.log('Users found:');
                    data.forEach((u, i) => {
                        console.log(\`  \${i+1}. \${u.email || 'No email'} (ID: \${u.id})\`);
                        console.log(\`     Created: \${u.created_at}\`);
                    });
                } else {
                    console.log('No users found.');
                }
            " 2>/dev/null || echo "Could not list users via API. Try using SQL Editor."
        
    elif [ "$ACTION" = "clear" ]; then
        echo "🗑️  Clearing test user from $env..."
        echo "Email: pythwk8m57@privaterelay.appleid.com"
        echo ""
        
        export SUPABASE_URL="$supabase_url"
        export SUPABASE_SERVICE_ROLE_KEY="$service_role_key"
        
        cd "$PROJECT_ROOT"
        deno run --allow-net --allow-env --allow-read \
            supabase/tests/reset_my_user.ts \
            --force \
            pythwk8m57@privaterelay.appleid.com 2>&1 || {
            echo "⚠️  User not found or already deleted"
        }
    else
        echo "Error: Invalid action. Use 'list' or 'clear'"
        return 1
    fi
    
    echo ""
}

# Main execution
echo "=========================================="
echo "Test Data Management"
echo "=========================================="
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    process_env "staging"
    echo ""
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    if [ "$ACTION" = "clear" ] && [ "$ENVIRONMENT" = "production" ]; then
        echo "⚠️  WARNING: About to clear production data!"
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    process_env "production"
    echo ""
fi

echo "=========================================="
echo "✅ Complete!"
echo "=========================================="

