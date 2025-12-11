#!/bin/bash
# ==============================================================================
# PAC Backend Test Runner
# ==============================================================================
# Runs all Deno tests for the Pay Attention Club backend.
# 
# Usage:
#   ./run_backend_tests.sh [staging|production]  # Run tests against specified environment
#   ./run_backend_tests.sh staging               # Run against staging (default)
#   ./run_backend_tests.sh production            # Run against production
#
# Prerequisites:
#   1. Deno installed (https://deno.land)
#   2. .env file in project root with:
#      - STAGING_SUPABASE_URL, STAGING_SUPABASE_SERVICE_ROLE_KEY (for staging)
#      - PRODUCTION_SUPABASE_URL, PRODUCTION_SUPABASE_SERVICE_ROLE_KEY (for production)
#      - STRIPE_SECRET_KEY_TEST (optional, for payment tests)
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Navigate to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Determine environment (default to staging)
TEST_ENV="${1:-staging}"
if [ "$TEST_ENV" != "staging" ] && [ "$TEST_ENV" != "production" ]; then
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

echo ""
echo "🧪 PAC Backend Test Suite"
echo "========================="
echo "Environment: $(echo $TEST_ENV | tr '[:lower:]' '[:upper:]')"
echo ""

# Check for .env file
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}❌ Error: .env file not found at $PROJECT_ROOT/.env${NC}"
    echo "   Create .env with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY"
    exit 1
fi

# Check for Deno
if ! command -v deno &> /dev/null; then
    echo -e "${RED}❌ Error: Deno not installed${NC}"
    echo "   Install from: https://deno.land"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found .env file"
echo -e "${GREEN}✓${NC} Deno version: $(deno --version | head -1)"
echo ""

# Source the .env file to export variables
echo "Loading environment variables..."
set -a  # Auto-export all variables
source "$PROJECT_ROOT/.env"
set +a

# Set TEST_ENVIRONMENT for the test config
export TEST_ENVIRONMENT="$TEST_ENV"

echo -e "${GREEN}✓${NC} Environment loaded (${TEST_ENV})"
echo ""

# Change to test directory
cd "$SCRIPT_DIR"

# Run tests
echo "Running tests..."
echo ""

if deno test \
    test_*.ts \
    --allow-net \
    --allow-env \
    --allow-read; then
    echo ""
    echo -e "${GREEN}════════════════════════════${NC}"
    echo -e "${GREEN}  All tests passed! 🎉${NC}"
    echo -e "${GREEN}════════════════════════════${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}════════════════════════════${NC}"
    echo -e "${RED}  Some tests failed! ❌${NC}"
    echo -e "${RED}════════════════════════════${NC}"
    exit 1
fi

