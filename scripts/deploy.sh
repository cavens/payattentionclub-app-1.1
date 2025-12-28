#!/bin/bash
# Deployment script - Runs checks, tests, commits/pushes changes, and deploys to Supabase
# Usage: ./scripts/deploy.sh [staging|production] [commit-message]
#        ./scripts/deploy.sh staging "feat: Update code"
#        ./scripts/deploy.sh production "feat: Release v1.0"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Parse arguments
ENVIRONMENT="${1:-staging}"
if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "production" ]; then
    # If first arg is not staging/production, treat it as commit message (backward compatibility)
    COMMIT_MESSAGE="${1:-feat: Update code}"
    ENVIRONMENT="staging"
else
    COMMIT_MESSAGE="${2:-feat: Update code}"
fi

echo "=========================================="
echo "🚀 Deployment Script"
echo "=========================================="
echo "Environment: $(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')"
echo ""

# Load .env for Supabase credentials
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Set environment-specific variables
if [ "$ENVIRONMENT" = "staging" ]; then
    SUPABASE_URL="$STAGING_SUPABASE_URL"
    SUPABASE_SECRET_KEY="$STAGING_SUPABASE_SECRET_KEY"
    SUPABASE_PROJECT_REF="auqujbppoytkeqdsgrbl"
elif [ "$ENVIRONMENT" = "production" ]; then
    SUPABASE_URL="$PRODUCTION_SUPABASE_URL"
    SUPABASE_SECRET_KEY="$PRODUCTION_SUPABASE_SECRET_KEY"
    SUPABASE_PROJECT_REF="whdftvcrtrsnefhprebj"
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SECRET_KEY" ]; then
    echo "⚠️  Warning: Missing Supabase environment variables for $ENVIRONMENT"
    echo "   Skipping Supabase deployments (RPC and Edge functions)"
    echo ""
fi

# Step 1: Check for secrets
echo "📋 Step 1: Checking for secrets..."
if ! ./scripts/check_secrets.sh; then
    echo "❌ Secrets check failed. Aborting deployment."
    exit 1
fi
echo "✅ Secrets check passed"
echo ""

# Step 2: Run tests
echo "📋 Step 2: Running tests..."
if ! ./scripts/run_all_tests.sh; then
    echo "⚠️  Some tests failed. Continue anyway? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "❌ Deployment aborted by user"
        exit 1
    fi
fi
echo "✅ Tests completed"
echo ""

# Step 3: Stage changes
echo "📋 Step 3: Staging changes..."
git add -A
echo "✅ Changes staged"
echo ""

# Step 4: Commit
echo "📋 Step 4: Committing changes..."
if git diff --staged --quiet; then
    echo "⚠️  No changes to commit"
else
    git commit -m "$COMMIT_MESSAGE"
    echo "✅ Changes committed"
fi
echo ""

# Step 5: Push
echo "📋 Step 5: Pushing to remote..."
git push
echo "✅ Changes pushed to remote"
echo ""

# Step 6: Deploy RPC Functions
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_SECRET_KEY" ]; then
    echo "📋 Step 6: Deploying RPC Functions to $ENVIRONMENT..."
    
    RPC_DIR="$PROJECT_ROOT/supabase/remote_rpcs"
    if [ -d "$RPC_DIR" ]; then
        DEPLOYED_COUNT=0
        FAILED_COUNT=0
        
        for sql_file in "$RPC_DIR"/*.sql; do
            if [ -f "$sql_file" ]; then
                filename=$(basename "$sql_file")
                echo "  Deploying $filename..."
                
                # Deploy RPC function
                # Note: RPC functions need to be deployed via Supabase Dashboard SQL Editor
                # or using a direct database connection. We'll use the run_sql_via_api.sh script
                # which requires rpc_execute_sql to exist. If it doesn't, manual deployment is needed.
                
                SQL_CONTENT=$(cat "$sql_file")
                
                # Try using run_sql_via_api.sh (requires rpc_execute_sql RPC to exist)
                if "$SCRIPT_DIR/run_sql_via_api.sh" "$ENVIRONMENT" "$SQL_CONTENT" >/dev/null 2>&1; then
                    echo "    ✅ $filename deployed via API"
                    DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
                else
                    # If rpc_execute_sql doesn't exist, provide manual instructions
                    echo "    ⚠️  Automatic deployment failed for $filename"
                    echo "       This is normal if rpc_execute_sql doesn't exist yet"
                    echo "       Manual deployment:"
                    echo "       1. Go to Supabase Dashboard → SQL Editor"
                    echo "       2. Copy contents of: $sql_file"
                    echo "       3. Paste and execute"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                fi
            fi
        done
        
        echo "  RPC Functions: $DEPLOYED_COUNT deployed, $FAILED_COUNT failed/skipped"
    else
        echo "  ⚠️  RPC directory not found: $RPC_DIR"
    fi
    echo ""
else
    echo "📋 Step 6: Skipping RPC Functions deployment (missing credentials)"
    echo ""
fi

# Step 7: Deploy Edge Functions
if [ -n "$SUPABASE_PROJECT_REF" ] && command -v supabase >/dev/null 2>&1; then
    echo "📋 Step 7: Deploying Edge Functions to $ENVIRONMENT..."
    
    FUNCTIONS_DIR="$PROJECT_ROOT/supabase/functions"
    if [ -d "$FUNCTIONS_DIR" ]; then
        # Link to the correct project
        supabase link --project-ref "$SUPABASE_PROJECT_REF" >/dev/null 2>&1 || true
        
        DEPLOYED_COUNT=0
        FAILED_COUNT=0
        
        # Deploy each edge function
        for func_dir in "$FUNCTIONS_DIR"/*/; do
            if [ -d "$func_dir" ] && [ -f "$func_dir/index.ts" ] || [ -f "$func_dir"/*.ts ]; then
                func_name=$(basename "$func_dir")
                echo "  Deploying $func_name..."
                
                if supabase functions deploy "$func_name" --project-ref "$SUPABASE_PROJECT_REF" 2>&1 | grep -q "Deployed\|deployed\|Success"; then
                    echo "    ✅ $func_name deployed"
                    DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
                else
                    # Try again with verbose output to see what happened
                    if supabase functions deploy "$func_name" --project-ref "$SUPABASE_PROJECT_REF" >/dev/null 2>&1; then
                        echo "    ✅ $func_name deployed"
                        DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
                    else
                        echo "    ⚠️  $func_name deployment failed or skipped"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    fi
                fi
            fi
        done
        
        echo "  Edge Functions: $DEPLOYED_COUNT deployed, $FAILED_COUNT failed/skipped"
    else
        echo "  ⚠️  Functions directory not found: $FUNCTIONS_DIR"
    fi
    echo ""
else
    echo "📋 Step 7: Skipping Edge Functions deployment (Supabase CLI not available or missing project ref)"
    echo ""
fi

echo "=========================================="
echo "✅ Deployment complete!"
echo "=========================================="


