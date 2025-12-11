#!/bin/bash
# ==============================================================================
# Verify Cron Jobs Setup
# ==============================================================================
# Checks if cron jobs are properly configured for weekly-close
# 
# Usage:
#   ./scripts/verify_cron_jobs.sh [staging|production|both]
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

# Function to verify cron for an environment
verify_cron_for_env() {
    local env=$1
    local project_ref
    local db_url
    
    if [ "$env" = "staging" ]; then
        project_ref="auqujbppoytkeqdsgrbl"
        db_url="$STAGING_DB_URL"
        echo "Verifying cron job for STAGING..."
    elif [ "$env" = "production" ]; then
        project_ref="whdftvcrtrsnefhprebj"
        db_url="$PRODUCTION_DB_URL"
        echo "Verifying cron job for PRODUCTION..."
    else
        echo "Error: Invalid environment: $env"
        return 1
    fi
    
    if [ -z "$db_url" ]; then
        echo "❌ Error: Database URL not found in .env for $env"
        return 1
    fi
    
    echo ""
    echo "Project: $project_ref"
    echo ""
    
    # Create verification SQL
    local sql_file="/tmp/verify_cron_${env}.sql"
    cat > "$sql_file" <<EOF
-- Verify Cron Job Setup ($env)
-- ==========================================

-- 1. Check if pg_cron extension is enabled
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') 
        THEN '✅ pg_cron extension is enabled'
        ELSE '❌ pg_cron extension is NOT enabled'
    END AS pg_cron_status;

-- 2. Check if service_role_key is set
SELECT 
    CASE 
        WHEN current_setting('app.settings.service_role_key', true) IS NOT NULL 
        THEN '✅ service_role_key is set'
        ELSE '❌ service_role_key is NOT set (needs manual setup in Dashboard)'
    END AS service_role_key_status;

-- 3. Check if call_weekly_close function exists
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'call_weekly_close') 
        THEN '✅ call_weekly_close function exists'
        ELSE '❌ call_weekly_close function does NOT exist'
    END AS function_status;

-- 4. Check if cron job is scheduled
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-close-$env') 
        THEN '✅ Cron job is scheduled'
        ELSE '❌ Cron job is NOT scheduled'
    END AS cron_job_status;

-- 5. Show cron job details (if exists)
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

    echo "Running verification queries..."
    
    if command -v psql >/dev/null 2>&1; then
        export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
        PGPASSWORD=$(echo "$db_url" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p') psql "$db_url" -f "$sql_file" 2>&1 | grep -v "password" || true
    else
        echo "⚠️  psql not found. Please run the SQL manually in Supabase Dashboard:"
        echo "   SQL file: $sql_file"
    fi
    
    echo ""
}

# Main execution
echo "=========================================="
echo "Cron Jobs Verification"
echo "=========================================="
echo ""

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "staging" ]; then
    verify_cron_for_env "staging"
    echo ""
fi

if [ "$ENVIRONMENT" = "both" ] || [ "$ENVIRONMENT" = "production" ]; then
    verify_cron_for_env "production"
    echo ""
fi

echo "=========================================="
echo "Verification Complete!"
echo "=========================================="

