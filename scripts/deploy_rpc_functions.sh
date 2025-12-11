#!/bin/bash

# Script to deploy all RPC functions to the linked Supabase project
# Usage: ./scripts/deploy_rpc_functions.sh [staging|production]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RPC_DIR="$PROJECT_ROOT/supabase/remote_rpcs"

ENVIRONMENT="${1:-staging}"

if [ "$ENVIRONMENT" = "staging" ]; then
    PROJECT_REF="auqujbppoytkeqdsgrbl"
    echo "Deploying RPC functions to STAGING..."
elif [ "$ENVIRONMENT" = "production" ]; then
    PROJECT_REF="whdftvcrtrsnefhprebj"
    echo "Deploying RPC functions to PRODUCTION..."
else
    echo "Error: Invalid environment. Use 'staging' or 'production'"
    exit 1
fi

# Link to the correct project
echo "Linking to $ENVIRONMENT project..."
cd "$PROJECT_ROOT"
supabase link --project-ref "$PROJECT_REF" > /dev/null 2>&1

# Load environment variables from .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a  # Auto-export all variables
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Add PostgreSQL to PATH if installed via Homebrew
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

# Check if we have a database connection string and psql
PSQL_CMD=$(command -v psql || echo "/opt/homebrew/opt/postgresql@17/bin/psql")

if [ "$ENVIRONMENT" = "staging" ]; then
    if [ -z "$STAGING_DB_URL" ]; then
        echo "⚠️  STAGING_DB_URL not set. Will use SQL Editor method."
        USE_PSQL=false
    elif [ ! -f "$PSQL_CMD" ]; then
        USE_PSQL=false
        echo "⚠️  psql not found. Will provide SQL Editor instructions."
    else
        USE_PSQL=true
        DB_URL="$STAGING_DB_URL"
    fi
else
    if [ -z "$PRODUCTION_DB_URL" ]; then
        echo "⚠️  PRODUCTION_DB_URL not set. Will use SQL Editor method."
        USE_PSQL=false
    elif [ ! -f "$PSQL_CMD" ]; then
        USE_PSQL=false
        echo "⚠️  psql not found. Will provide SQL Editor instructions."
    else
        USE_PSQL=true
        DB_URL="$PRODUCTION_DB_URL"
    fi
fi

echo ""
echo "Found RPC functions:"
ls -1 "$RPC_DIR"/*.sql | xargs -n1 basename
echo ""

if [ "$USE_PSQL" = true ]; then
    echo "Deploying via psql..."
    for rpc_file in "$RPC_DIR"/*.sql; do
        filename=$(basename "$rpc_file")
        echo "  → Deploying $filename..."
        "$PSQL_CMD" "$DB_URL" -f "$rpc_file" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "    ✅ Success"
        else
            echo "    ❌ Failed"
            exit 1
        fi
    done
    echo ""
    echo "✅ All RPC functions deployed successfully!"
else
    echo "📋 Manual deployment required:"
    echo ""
    echo "1. Go to: https://supabase.com/dashboard/project/$PROJECT_REF/sql/new"
    echo "2. For each file in $RPC_DIR:"
    echo "   - Open the .sql file"
    echo "   - Copy its contents"
    echo "   - Paste into SQL Editor"
    echo "   - Click 'Run'"
    echo ""
    echo "Files to deploy:"
    ls -1 "$RPC_DIR"/*.sql | xargs -n1 basename | sed 's/^/   - /'
    echo ""
    echo "Or install psql and set DB_URL to automate this:"
    echo "  brew install postgresql"
    echo "  export STAGING_DB_URL='postgresql://postgres:[PASSWORD]@db.$PROJECT_REF.supabase.co:5432/postgres'"
fi

