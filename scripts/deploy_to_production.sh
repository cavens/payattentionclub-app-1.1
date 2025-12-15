#!/bin/bash
# ==============================================================================
# Deploy SQL/RPC Functions to Production
# ==============================================================================
# Deploys all SQL/RPC functions from supabase/remote_rpcs/ to production Supabase.
# 
# Usage:
#   ./scripts/deploy_to_production.sh
#
# Prerequisites:
#   - .env file with PRODUCTION_SUPABASE_URL and PRODUCTION_SUPABASE_SECRET_KEY
#   - rpc_execute_sql function must exist in production database
#   - You should be on the 'main' branch
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RPC_DIR="$PROJECT_ROOT/supabase/remote_rpcs"

cd "$PROJECT_ROOT"

echo ""
echo -e "${RED}${BOLD}🚀 Deploy to PRODUCTION${NC}"
echo "===================="
echo ""

# ==============================================================================
# Step 1: Check Git Branch
# ==============================================================================
echo -e "${BLUE}Step 1: Checking git branch...${NC}"
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${YELLOW}⚠️  Warning: You're not on 'main' branch (currently on: $CURRENT_BRANCH)${NC}"
    read -p "Continue anyway? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
else
    echo -e "${GREEN}✅ On 'main' branch${NC}"
fi
echo ""

# ==============================================================================
# Step 2: Secrets Safety Check (MANDATORY)
# ==============================================================================
echo -e "${BLUE}Step 2: Checking for secrets...${NC}"
if ! "$SCRIPT_DIR/check_secrets.sh"; then
    echo ""
    echo -e "${RED}❌ Secrets check failed!${NC}"
    echo "Please remove secrets from your code before deploying to production."
    echo ""
    exit 1
fi
echo -e "${GREEN}✅ No secrets found${NC}"
echo ""

# ==============================================================================
# Step 3: Load Environment Variables
# ==============================================================================
echo -e "${BLUE}Step 3: Loading environment variables...${NC}"
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    exit 1
fi

# Source .env file
set -a
source "$PROJECT_ROOT/.env"
set +a

# Check required variables
if [ -z "$PRODUCTION_SUPABASE_URL" ] || [ -z "$PRODUCTION_SUPABASE_SECRET_KEY" ]; then
    echo -e "${RED}❌ Error: Missing required environment variables${NC}"
    echo "   Required: PRODUCTION_SUPABASE_URL, PRODUCTION_SUPABASE_SECRET_KEY"
    exit 1
fi

# Verify we're using production URLs (safety check)
if echo "$PRODUCTION_SUPABASE_URL" | grep -q "auqujbppoytkeqdsgrbl"; then
    echo -e "${RED}❌ ERROR: PRODUCTION_SUPABASE_URL appears to be staging URL!${NC}"
    echo "   Staging project: auqujbppoytkeqdsgrbl"
    echo "   Production project: whdftvcrtrsnefhprebj"
    exit 1
fi

echo -e "${GREEN}✅ Environment variables loaded${NC}"
echo "   URL: $PRODUCTION_SUPABASE_URL"
echo ""

# ==============================================================================
# Step 4: Confirmation Prompt
# ==============================================================================
echo -e "${RED}${BOLD}⚠️  WARNING: You are about to deploy to PRODUCTION${NC}"
echo ""
echo "This will:"
echo "  - Deploy all SQL/RPC functions to production Supabase"
echo "  - Affect live users"
echo "  - Cannot be easily undone"
echo ""
read -p "Type 'DEPLOY' to confirm: " -r
if [ "$REPLY" != "DEPLOY" ]; then
    echo "Deployment cancelled."
    exit 1
fi
echo ""

# ==============================================================================
# Step 5: Find SQL Files
# ==============================================================================
echo -e "${BLUE}Step 5: Finding SQL files...${NC}"
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
# Step 6: Deploy Each SQL File
# ==============================================================================
echo -e "${BLUE}Step 6: Deploying SQL files to PRODUCTION...${NC}"
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
        "${PRODUCTION_SUPABASE_URL}/rest/v1/rpc/rpc_execute_sql" \
        -H "apikey: ${PRODUCTION_SUPABASE_SECRET_KEY}" \
        -H "Authorization: Bearer ${PRODUCTION_SUPABASE_SECRET_KEY}" \
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
# Step 7: Summary
# ==============================================================================
echo "===================="
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All $SUCCESS_COUNT file(s) deployed successfully to PRODUCTION!${NC}"
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
    echo -e "${YELLOW}⚠️  Some files failed. Please check the errors above.${NC}"
    exit 1
fi

