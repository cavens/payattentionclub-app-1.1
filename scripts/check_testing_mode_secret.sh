#!/bin/bash
# ==============================================================================
# Check TESTING_MODE Secret Value
# ==============================================================================
# This script calls the check-secret Edge Function to verify the TESTING_MODE
# secret value matches what's in the database.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

SUPABASE_URL="${STAGING_SUPABASE_URL:-$SUPABASE_URL}"
SUPABASE_SECRET_KEY="${STAGING_SUPABASE_SECRET_KEY:-$SUPABASE_SECRET_KEY}"

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SECRET_KEY" ]; then
    echo "❌ Error: Missing SUPABASE_URL or SUPABASE_SECRET_KEY"
    exit 1
fi

echo "🔍 Checking TESTING_MODE secret value..."
echo ""

# Call check-secret function
RESPONSE=$(curl -s -X POST "${SUPABASE_URL}/functions/v1/check-secret" \
  -H "Authorization: Bearer ${SUPABASE_SECRET_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"secretName": "TESTING_MODE"}')

echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"

echo ""
echo "📊 Compare with database value:"
echo "   Run in SQL Editor: SELECT value FROM app_config WHERE key = 'testing_mode';"
echo "   Values should match!"

