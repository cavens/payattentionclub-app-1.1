#!/bin/bash
# ==============================================================================
# PAC Backend Test Runner
# ==============================================================================
# Runs all Deno tests for the Pay Attention Club backend.
# 
# Usage:
#   ./run_backend_tests.sh           # Run all tests
#   ./run_backend_tests.sh --quick   # Run with shorter timeout
#
# Prerequisites:
#   1. Deno installed (https://deno.land)
#   2. .env file in project root with:
#      - SUPABASE_URL
#      - SUPABASE_SERVICE_ROLE_KEY
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

echo ""
echo "🧪 PAC Backend Test Suite"
echo "========================="
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
echo -e "${GREEN}✓${NC} Environment loaded"
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

