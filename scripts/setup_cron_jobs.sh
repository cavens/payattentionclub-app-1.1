#!/bin/bash
# ==============================================================================
# Setup Cron Jobs for Weekly Close (Phase 6)
# ==============================================================================
# Sets up pg_cron jobs to automatically call bright-service Edge Function
# via call_weekly_close() RPC function
# 
# Note: call_weekly_close() now routes to bright-service (replaces weekly-close)
# 
# Current schedule: Every Monday at 12:00 PM EST (17:00 UTC)
# Note: Consider updating to Tuesday 12:00 ET to run after grace period expires
# 
# Usage:
#   ./scripts/setup_cron_jobs.sh [staging|production|both]
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
    local db_url
    local service_role_key
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        db_url="$STAGING_DB_URL"
        supabase_secret_key="$STAGING_SUPABASE_SECRET_KEY"
        supabase_url="$STAGING_SUPABASE_URL"
        echo "Setting up cron job for STAGING..."
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        db_url="$PRODUCTION_DB_URL"
        supabase_secret_key="$PRODUCTION_SUPABASE_SECRET_KEY"
        supabase_url="$PRODUCTION_SUPABASE_URL"
        echo "Setting up cron job for PRODUCTION..."
    else
        echo "Error: Invalid environment: $env"
        return 1
    fi
    
    if [ -z "$db_url" ]; then
        echo "❌ Error: Database URL not found in .env for $env"
        return 1
    fi
    
    if [ -z "$supabase_secret_key" ]; then
        echo "❌ Error: Supabase secret key not found in .env for $env"
        return 1
    fi
    
    if [ -z "$supabase_url" ]; then
        echo "❌ Error: Supabase URL not found in .env for $env"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo "Database URL: ${db_url%%@*}" # Hide password
    echo ""
    
    # Create SQL script
    local sql_file="/tmp/setup_cron_${env}.sql"
    cat > "$sql_file" <<EOF
-- Setup Cron Job for Weekly Close ($env)
-- ==========================================
-- Note: call_weekly_close() now routes to bright-service (replaces weekly-close)

-- Step 1: Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Step 2: Set app.settings (required for call_weekly_close function)
-- Note: This uses ALTER DATABASE which requires superuser privileges
-- If this fails, you may need to set it manually in Supabase Dashboard
DO \$\$
BEGIN
    -- Set service_role_key
    EXECUTE format('ALTER DATABASE postgres SET app.settings.service_role_key = %L', '$supabase_secret_key');
    -- Set supabase_url (for environment-aware Edge Function calls)
    EXECUTE format('ALTER DATABASE postgres SET app.settings.supabase_url = %L', '$supabase_url');
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'Cannot set app.settings via SQL. Please set it manually in Supabase Dashboard → Database → Settings → Database Settings → Custom Postgres Config';
        RAISE NOTICE 'Required settings: app.settings.service_role_key and app.settings.supabase_url';
    WHEN OTHERS THEN
        RAISE WARNING 'Error setting app.settings: %', SQLERRM;
END;
\$\$;

-- Step 3: Remove existing cron job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-$env';

-- Step 4: Schedule new cron job
-- Schedule: Every Monday at 17:00 UTC (12:00 PM EST / 1:00 PM EDT)
-- Cron format: minute hour day-of-month month day-of-week
-- 0 17 * * 1 = Every Monday at 17:00 UTC
SELECT cron.schedule(
    'weekly-close-$env',           -- Job name
    '0 17 * * 1',                   -- Schedule: Every Monday at 17:00 UTC
    \$\$SELECT public.call_weekly_close();\$\$  -- Call the function
);

-- Step 5: Verify the job was created
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active,
    nodename,
    nodeport
FROM cron.job
WHERE jobname = 'weekly-close-$env';
EOF

    echo "Executing SQL script..."
    
    # Find psql in common locations
    local psql_path=""
    if command -v psql >/dev/null 2>&1; then
        psql_path="psql"
    elif [ -f "/usr/local/bin/psql" ]; then
        psql_path="/usr/local/bin/psql"
    elif [ -f "/opt/homebrew/bin/psql" ]; then
        psql_path="/opt/homebrew/bin/psql"
    elif [ -f "/Applications/Postgres.app/Contents/Versions/latest/bin/psql" ]; then
        psql_path="/Applications/Postgres.app/Contents/Versions/latest/bin/psql"
    fi
    
    # Execute SQL using psql
    if [ -n "$psql_path" ]; then
        echo "Using psql: $psql_path"
        
        # Extract connection details from URL
        # Format: postgresql://user:password@host:port/database
        local db_user=$(echo "$db_url" | sed -n 's|.*://\([^:]*\):.*|\1|p')
        local db_pass=$(echo "$db_url" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
        local db_host=$(echo "$db_url" | sed -n 's|.*@\([^:]*\):.*|\1|p')
        local db_port=$(echo "$db_url" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
        local db_name=$(echo "$db_url" | sed -n 's|.*/\([^?]*\).*|\1|p')
        
        # URL decode password (handle %23, %24, etc.)
        db_pass=$(printf '%b' "${db_pass//%/\\x}")
        
        # Execute SQL
        PGPASSWORD="$db_pass" "$psql_path" \
            -h "$db_host" \
            -p "${db_port:-5432}" \
            -U "$db_user" \
            -d "$db_name" \
            -f "$sql_file" \
            2>&1 | grep -v "password" || {
            echo "⚠️  Note: Some operations may require manual setup in Supabase Dashboard"
        }
    else
        echo "❌ Error: psql not found."
        echo ""
        echo "To install psql:"
        echo "  brew install postgresql@15"
        echo "  # or"
        echo "  brew install postgresql"
        echo ""
        echo "Or run the SQL manually:"
        echo "  SQL file: $sql_file"
        echo "  Or run it in Supabase Dashboard → SQL Editor"
        echo ""
        return 1
    fi
    
    echo ""
    echo "✅ Cron job setup complete for $env!"
    echo ""
}

# Main execution
echo "=========================================="
echo "Phase 6: Cron Jobs Setup"
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
echo "✅ Phase 6 Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Verify cron jobs in Supabase Dashboard → Database → Cron Jobs"
echo "2. Check that supabase_secret_key is set (if SQL failed)"
echo "3. Test by manually calling: SELECT public.call_weekly_close();"
echo "4. Monitor logs on next Monday at 17:00 UTC"

