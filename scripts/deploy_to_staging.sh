#!/bin/bash
# ==============================================================================
# Deploy SQL/RPC Functions to Staging
# ==============================================================================
# Deploys all SQL/RPC functions from supabase/remote_rpcs/ to staging Supabase.
# 
# Usage:
#   ./scripts/deploy_to_staging.sh
#
# Prerequisites:
#   - .env file with STAGING_SUPABASE_URL and STAGING_SUPABASE_SECRET_KEY
#   - rpc_execute_sql function must exist in staging database
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RPC_DIR="$PROJECT_ROOT/supabase/remote_rpcs"

cd "$PROJECT_ROOT"

echo ""
echo "🚀 Deploy to Staging"
echo "===================="
echo ""

# ==============================================================================
# Step 1: Secrets Safety Check (MANDATORY)
# ==============================================================================
echo -e "${BLUE}Step 1: Checking for secrets...${NC}"
if ! "$SCRIPT_DIR/check_secrets.sh"; then
    echo ""
    echo -e "${RED}❌ Secrets check failed!${NC}"
    echo "Please remove secrets from your code before deploying."
    echo ""
    exit 1
fi
echo -e "${GREEN}✅ No secrets found${NC}"
echo ""

# ==============================================================================
# Step 2: Load Environment Variables
# ==============================================================================
echo -e "${BLUE}Step 2: Loading environment variables...${NC}"
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    exit 1
fi

# Source .env file
set -a
source "$PROJECT_ROOT/.env"
set +a

# Check required variables
if [ -z "$STAGING_SUPABASE_URL" ] || [ -z "$STAGING_SUPABASE_SECRET_KEY" ]; then
    echo -e "${RED}❌ Error: Missing required environment variables${NC}"
    echo "   Required: STAGING_SUPABASE_URL, STAGING_SUPABASE_SECRET_KEY"
    exit 1
fi

echo -e "${GREEN}✅ Environment variables loaded${NC}"
echo ""

# ==============================================================================
# Step 3: Find SQL Files
# ==============================================================================
echo -e "${BLUE}Step 3: Finding SQL files...${NC}"
if [ ! -d "$RPC_DIR" ]; then
    echo -e "${RED}❌ Error: RPC directory not found: $RPC_DIR${NC}"
    exit 1
fi

SQL_FILES=$(find "$RPC_DIR" -name "*.sql" -type f | sort)

if [ -z "$SQL_FILES" ]; then
    echo -e "${YELLOW}⚠️  No SQL files found in $RPC_DIR${NC}"
    exit 0
fi

FILE_COUNT=$(echo "$SQL_FILES" | wc -l | tr -d ' ')
echo -e "${GREEN}✅ Found $FILE_COUNT SQL file(s)${NC}"
echo ""

# ==============================================================================
# Step 4: Deploy Each SQL File
# ==============================================================================
echo -e "${BLUE}Step 4: Deploying SQL files...${NC}"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_FILES=()

while IFS= read -r sql_file; do
    filename=$(basename "$sql_file")
    echo -n "  → Deploying $filename... "
    
    # Read SQL content
    SQL_CONTENT=$(cat "$sql_file")
    
    # Call Supabase API to execute SQL
    RESPONSE=$(curl -s -X POST \
        "${STAGING_SUPABASE_URL}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${STAGING_SUPABASE_SECRET_KEY}" \
        -H "Authorization: Bearer ${STAGING_SUPABASE_SECRET_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"p_sql\": $(echo "$SQL_CONTENT" | jq -Rs .)}" 2>&1)
    
    # Check if jq is available for parsing
    if command -v jq >/dev/null 2>&1; then
        SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false' 2>/dev/null || echo "false")
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // .message // ""' 2>/dev/null || echo "")
    else
        # Fallback: check for success in response
        if echo "$RESPONSE" | grep -q '"success":true'; then
            SUCCESS="true"
        else
            SUCCESS="false"
            ERROR_MSG="$RESPONSE"
        fi
    fi
    
    if [ "$SUCCESS" = "true" ]; then
        echo -e "${GREEN}✅${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}❌${NC}"
        if [ -n "$ERROR_MSG" ]; then
            echo "     Error: $ERROR_MSG" | head -1
        fi
        ((FAIL_COUNT++))
        FAILED_FILES+=("$filename")
    fi
done <<< "$SQL_FILES"

echo ""

# ==============================================================================
# Step 5: Summary
# ==============================================================================
echo "===================="
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All $SUCCESS_COUNT file(s) deployed successfully!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Deployment failed!${NC}"
    echo "   Success: $SUCCESS_COUNT"
    echo "   Failed: $FAIL_COUNT"
    echo ""
    echo "Failed files:"
    for file in "${FAILED_FILES[@]}"; do
        echo "   - $file"
    done
    echo ""
    exit 1
fi

