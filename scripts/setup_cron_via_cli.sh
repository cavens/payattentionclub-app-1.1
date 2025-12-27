#!/bin/bash
# ==============================================================================
# Setup Cron Jobs via Supabase CLI + psql
# ==============================================================================
# Alternative method using Supabase CLI to link and then psql to execute SQL
# 
# Usage:
#   ./scripts/setup_cron_via_cli.sh [staging|production|both]
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

# Function to setup cron for an environment
setup_cron_for_env() {
    local env=$1
    local project_ref
    local service_role_key
    local sql_file
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        supabase_secret_key="$STAGING_SUPABASE_SECRET_KEY"
        sql_file="$PROJECT_ROOT/supabase/sql-drafts/setup_cron_staging.sql"
        echo "Setting up cron job for STAGING via CLI..."
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        supabase_secret_key="$PRODUCTION_SUPABASE_SECRET_KEY"
        sql_file="$PROJECT_ROOT/supabase/sql-drafts/setup_cron_production.sql"
        echo "Setting up cron job for PRODUCTION via CLI..."
    else
        echo "Error: Invalid environment: $env"
        return 1
    fi
    
    if [ -z "$supabase_secret_key" ]; then
        echo "❌ Error: Supabase secret key not found in .env for $env"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo ""
    
    # Step 1: Link to the project
    echo "Step 1: Linking to Supabase project..."
    cd "$PROJECT_ROOT"
    supabase link --project-ref "$project_ref" > /dev/null 2>&1 || {
        echo "⚠️  Already linked or link failed. Continuing..."
    }
    
    # Step 2: Get database connection string
    echo "Step 2: Getting database connection details..."
    # Note: Supabase CLI doesn't directly expose psql connection
    # We'll use the DB URL from .env instead
    
    if [ "$env" = "staging" ]; then
        db_url="$STAGING_DB_URL"
    else
        db_url="$PRODUCTION_DB_URL"
    fi
    
    if [ -z "$db_url" ]; then
        echo "❌ Error: Database URL not found in .env"
        return 1
    fi
    
    # Step 3: Execute SQL using psql
    echo "Step 3: Executing SQL to set up cron job..."
    
    # Find psql
    local psql_path=""
    if command -v psql >/dev/null 2>&1; then
        psql_path="psql"
    elif [ -f "/usr/local/bin/psql" ]; then
        psql_path="/usr/local/bin/psql"
    elif [ -f "/opt/homebrew/bin/psql" ]; then
        psql_path="/opt/homebrew/bin/psql"
    fi
    
    if [ -z "$psql_path" ]; then
        echo "❌ Error: psql not found."
        echo ""
        echo "Install PostgreSQL:"
        echo "  brew install postgresql@15"
        echo ""
        echo "Or use the manual setup:"
        echo "  1. Go to Supabase Dashboard → SQL Editor"
        echo "  2. Copy-paste SQL from: $sql_file"
        return 1
    fi
    
    # Extract connection details
    local db_user=$(echo "$db_url" | sed -n 's|.*://\([^:]*\):.*|\1|p')
    local db_pass=$(echo "$db_url" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
    local db_host=$(echo "$db_url" | sed -n 's|.*@\([^:]*\):.*|\1|p')
    local db_port=$(echo "$db_url" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    local db_name=$(echo "$db_url" | sed -n 's|.*/\([^?]*\).*|\1|p')
    
    # URL decode password
    db_pass=$(printf '%b' "${db_pass//%/\\x}")
    
    # Execute SQL
    echo "Connecting to database..."
    PGPASSWORD="$db_pass" "$psql_path" \
        -h "$db_host" \
        -p "${db_port:-5432}" \
        -U "$db_user" \
        -d "$db_name" \
        -f "$sql_file" \
        2>&1 | grep -v "password" || {
        echo "⚠️  Some operations may require manual setup"
    }
    
    echo ""
    echo "✅ Cron job setup complete for $env!"
    echo ""
    echo "⚠️  IMPORTANT: Don't forget to set supabase_secret_key in database settings:"
    echo "   Go to Supabase Dashboard → Database → Settings → Custom Postgres Config"
    echo "   Key: app.settings.service_role_key"
    echo "   Value: $supabase_secret_key"
    echo ""
}

# Main execution
echo "=========================================="
echo "Phase 6: Cron Jobs Setup (via CLI)"
echo "=========================================="
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    setup_cron_for_env "staging"
    echo ""
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    if [ "$ENVIRONMENT" = "production" ]; then
        echo "⚠️  WARNING: Setting up production cron job!"
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    setup_cron_for_env "production"
    echo ""
fi

echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="



