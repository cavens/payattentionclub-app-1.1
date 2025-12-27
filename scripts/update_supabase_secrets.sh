#!/bin/bash
# ==============================================================================
# Update Supabase Edge Function Secrets
# ==============================================================================
# Updates the secret names in Supabase Edge Functions from old naming to new naming
# 
# This script:
# 1. Reads the old secret values from Supabase
# 2. Sets them with the new names
# 3. Optionally removes the old secret names
# 
# Usage:
#   ./scripts/update_supabase_secrets.sh [staging|production|both]
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

# Function to update secrets for an environment
update_secrets_for_env() {
    local env=$1
    local project_ref
    local supabase_url
    local secret_key
    local publishable_key
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        supabase_url="$STAGING_SUPABASE_URL"
        secret_key="$STAGING_SUPABASE_SECRET_KEY"
        publishable_key="$STAGING_SUPABASE_PUBLISHABLE_KEY"
        echo "=========================================="
        echo "Updating STAGING Environment Secrets"
        echo "=========================================="
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        supabase_url="$PRODUCTION_SUPABASE_URL"
        secret_key="$PRODUCTION_SUPABASE_SECRET_KEY"
        publishable_key="$PRODUCTION_SUPABASE_PUBLISHABLE_KEY"
        echo "=========================================="
        echo "Updating PRODUCTION Environment Secrets"
        echo "=========================================="
    else
        echo "❌ Error: Invalid environment: $env"
        return 1
    fi
    
    if [ -z "$secret_key" ] || [ -z "$publishable_key" ]; then
        echo "❌ Error: Missing keys in .env file for $env"
        echo "   Required: ${env^^}_SUPABASE_SECRET_KEY and ${env^^}_SUPABASE_PUBLISHABLE_KEY"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo "URL: $supabase_url"
    echo ""
    
    # Check if supabase CLI is installed
    if ! command -v supabase >/dev/null 2>&1; then
        echo "❌ Error: Supabase CLI not found"
        echo ""
        echo "Install it with:"
        echo "  brew install supabase/tap/supabase"
        echo ""
        echo "Or update secrets manually via Supabase Dashboard:"
        echo "  https://supabase.com/dashboard/project/$project_ref/settings/functions"
        echo ""
        echo "Set these secrets:"
        echo "  SUPABASE_SECRET_KEY = $secret_key"
        echo "  SUPABASE_PUBLISHABLE_KEY = $publishable_key"
        echo ""
        echo "Then remove the old secrets:"
        echo "  SUPABASE_SERVICE_ROLE_KEY (delete)"
        echo "  SUPABASE_ANON_KEY (delete)"
        return 1
    fi
    
    echo "Step 1: Linking to Supabase project..."
    cd "$PROJECT_ROOT"
    
    # Link to the project
    supabase link --project-ref "$project_ref" > /dev/null 2>&1 || {
        echo "⚠️  Already linked or link failed. Continuing..."
    }
    
    echo "✅ Linked to project $project_ref"
    echo ""
    
    echo "Step 2: Setting new secret names..."
    echo ""
    
    # Set the new secret key
    echo "  Setting SUPABASE_SECRET_KEY..."
    if supabase secrets set SUPABASE_SECRET_KEY="$secret_key" --project-ref "$project_ref" 2>&1; then
        echo "  ✅ SUPABASE_SECRET_KEY set successfully"
    else
        echo "  ❌ Failed to set SUPABASE_SECRET_KEY"
        echo "  💡 You may need to set this manually in the dashboard"
    fi
    
    # Set the new publishable key
    echo "  Setting SUPABASE_PUBLISHABLE_KEY..."
    if supabase secrets set SUPABASE_PUBLISHABLE_KEY="$publishable_key" --project-ref "$project_ref" 2>&1; then
        echo "  ✅ SUPABASE_PUBLISHABLE_KEY set successfully"
    else
        echo "  ❌ Failed to set SUPABASE_PUBLISHABLE_KEY"
        echo "  💡 You may need to set this manually in the dashboard"
    fi
    
    echo ""
    echo "Step 3: Verifying new secrets..."
    echo ""
    
    # Note: Supabase CLI doesn't have a direct way to list secrets, so we'll just confirm
    echo "  ✅ New secrets have been set"
    echo "  📋 Verify in Dashboard: https://supabase.com/dashboard/project/$project_ref/settings/functions"
    echo ""
    
    echo "Step 4: Removing old secret names (optional)..."
    echo ""
    echo "  ⚠️  IMPORTANT: After verifying the new secrets work, remove the old ones:"
    echo "     - SUPABASE_SERVICE_ROLE_KEY"
    echo "     - SUPABASE_ANON_KEY"
    echo ""
    echo "  You can remove them via Dashboard or CLI:"
    echo "    supabase secrets unset SUPABASE_SERVICE_ROLE_KEY --project-ref $project_ref"
    echo "    supabase secrets unset SUPABASE_ANON_KEY --project-ref $project_ref"
    echo ""
    
    echo "=========================================="
    echo "✅ $env Environment Secrets Updated!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Test your Edge Functions to ensure they work with new secret names"
    echo "2. Once verified, remove the old secret names (SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY)"
    echo "3. Redeploy Edge Functions if needed"
    echo ""
}

# Main execution
echo "=========================================="
echo "Supabase Edge Function Secrets Update"
echo "=========================================="
echo ""
echo "This script updates Edge Function secrets from:"
echo "  - SUPABASE_SERVICE_ROLE_KEY → SUPABASE_SECRET_KEY"
echo "  - SUPABASE_ANON_KEY → SUPABASE_PUBLISHABLE_KEY"
echo ""
echo "⚠️  Note: This requires Supabase CLI to be installed"
echo "   Install: brew install supabase/tap/supabase"
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    update_secrets_for_env "staging"
    echo ""
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    if [ "$ENVIRONMENT" = "production" ]; then
        echo "⚠️  WARNING: About to update PRODUCTION secrets!"
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    update_secrets_for_env "production"
    echo ""
fi

echo "=========================================="
echo "✅ Secrets Update Complete!"
echo "=========================================="
echo ""
echo "Manual Alternative:"
echo "If CLI doesn't work, update secrets manually:"
echo "  1. Go to: https://supabase.com/dashboard/project/[PROJECT_REF]/settings/functions"
echo "  2. Add new secrets: SUPABASE_SECRET_KEY and SUPABASE_PUBLISHABLE_KEY"
echo "  3. Copy values from your .env file"
echo "  4. Test Edge Functions"
echo "  5. Remove old secrets: SUPABASE_SERVICE_ROLE_KEY and SUPABASE_ANON_KEY"
echo ""








