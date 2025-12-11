#!/bin/bash
# ==============================================================================
# Execute SQL via Supabase REST API
# ==============================================================================
# Uses RPC function to execute SQL without direct psql connection
# 
# Usage:
#   ./scripts/run_sql_via_api.sh [staging|production] "SQL_QUERY"
#   ./scripts/run_sql_via_api.sh staging "SELECT COUNT(*) FROM users;"
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-staging}"
SQL_QUERY="${2}"

if [ -z "$SQL_QUERY" ]; then
    echo "Error: SQL query required"
    echo "Usage: $0 [staging|production] \"SQL_QUERY\""
    exit 1
fi

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Get environment-specific variables
if [ "$ENVIRONMENT" = "staging" ]; then
    SUPABASE_URL="$STAGING_SUPABASE_URL"
    SERVICE_ROLE_KEY="$STAGING_SUPABASE_SERVICE_ROLE_KEY"
    echo "Executing SQL in STAGING..."
elif [ "$ENVIRONMENT" = "production" ]; then
    SUPABASE_URL="$PRODUCTION_SUPABASE_URL"
    SERVICE_ROLE_KEY="$PRODUCTION_SUPABASE_SERVICE_ROLE_KEY"
    echo "Executing SQL in PRODUCTION..."
else
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
    echo "❌ Error: Missing environment variables"
    exit 1
fi

echo ""
echo "SQL Query:"
echo "$SQL_QUERY"
echo ""

# URL encode the SQL query
SQL_QUERY_ENCODED=$(printf '%s' "$SQL_QUERY" | jq -sRr @uri 2>/dev/null || python3 -c "import urllib.parse; print(urllib.parse.quote(input()))" <<< "$SQL_QUERY")

# Call RPC function via REST API
RESPONSE=$(curl -s -X POST \
    "${SUPABASE_URL}/rest/v1/rpc/rpc_execute_sql" \
    -H "apikey: ${SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"p_sql\": $(echo "$SQL_QUERY" | jq -Rs .)}")

# Check if jq is available for pretty printing
if command -v jq >/dev/null 2>&1; then
    echo "$RESPONSE" | jq .
else
    echo "$RESPONSE"
fi

# Check for errors
if echo "$RESPONSE" | grep -q '"success":false'; then
    echo ""
    echo "❌ SQL execution failed!"
    exit 1
else
    echo ""
    echo "✅ SQL executed successfully!"
fi

