#!/bin/bash
# ==============================================================================
# Setup app_config table with secrets from .env
# ==============================================================================
# 
# This script populates the app_config table with values from .env file.
# Secrets are NEVER committed to Git - they're read from .env at runtime.
# 
# Usage:
#   ./scripts/setup_app_config.sh [staging|production]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-staging}"

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Get environment-specific variables
if [ "$ENVIRONMENT" = "staging" ]; then
    SUPABASE_URL="$STAGING_SUPABASE_URL"
    SUPABASE_SECRET_KEY="$STAGING_SUPABASE_SECRET_KEY"
    echo "Setting up app_config for STAGING..."
elif [ "$ENVIRONMENT" = "production" ]; then
    SUPABASE_URL="$PRODUCTION_SUPABASE_URL"
    SUPABASE_SECRET_KEY="$PRODUCTION_SUPABASE_SECRET_KEY"
    echo "Setting up app_config for PRODUCTION..."
else
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SECRET_KEY" ]; then
    echo "❌ Error: Missing environment variables"
    echo "   Make sure ${ENVIRONMENT^^}_SUPABASE_URL and ${ENVIRONMENT^^}_SUPABASE_SECRET_KEY are set in .env"
    exit 1
fi

echo ""
echo "Supabase URL: $SUPABASE_URL"
echo "Service Role Key: ${SUPABASE_SECRET_KEY:0:20}...${SUPABASE_SECRET_KEY: -10}"
echo ""

# Escape single quotes in values for SQL (double them)
ESCAPED_SECRET_KEY=$(echo "$SUPABASE_SECRET_KEY" | sed "s/'/''/g")
ESCAPED_URL=$(echo "$SUPABASE_URL" | sed "s/'/''/g")

# Build SQL query
SQL="-- Update service_role_key
UPDATE public.app_config 
SET 
  value = '${ESCAPED_SECRET_KEY}',
  updated_at = NOW(),
  updated_by = 'setup_app_config.sh'
WHERE key = 'service_role_key';

-- Update supabase_url
UPDATE public.app_config 
SET 
  value = '${ESCAPED_URL}',
  updated_at = NOW(),
  updated_by = 'setup_app_config.sh'
WHERE key = 'supabase_url';

-- Verify values were set
SELECT 
  key,
  CASE 
    WHEN key = 'service_role_key' THEN '***HIDDEN***'
    ELSE value
  END as value,
  updated_at,
  updated_by
FROM public.app_config
WHERE key IN ('service_role_key', 'supabase_url')
ORDER BY key;"

echo "Updating app_config table..."
echo ""

# Execute via API
if [ -f "$SCRIPT_DIR/run_sql_via_api.sh" ]; then
    bash "$SCRIPT_DIR/run_sql_via_api.sh" "$ENVIRONMENT" "$SQL"
else
    echo "❌ Error: run_sql_via_api.sh not found"
    echo "   Please run this SQL manually in Supabase Dashboard → SQL Editor:"
    echo ""
    echo "$SQL"
    exit 1
fi

echo ""
echo "✅ app_config table updated successfully!"
echo ""
echo "⚠️  IMPORTANT: Secrets are stored in the database but:"
echo "   - Protected by RLS (only SECURITY DEFINER functions can read)"
echo "   - Encrypted at rest (PostgreSQL default)"
echo "   - Never committed to Git (.env is gitignored)"
