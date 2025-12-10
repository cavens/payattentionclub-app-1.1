#!/bin/bash
#
# PAC Test Suite - Master Test Runner
# Runs all backend (Deno) and iOS unit tests
#
# Usage: ./run_all_tests.sh
#

set -e  # Exit on first error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "============================================"
echo "🧪 PAC Test Suite"
echo "============================================"
echo ""

# Track results
BACKEND_RESULT=0
IOS_RESULT=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ------------------------------
# 1. Backend Tests (Deno)
# ------------------------------
echo -e "${BLUE}📦 Backend Tests (Deno)${NC}"
echo "------------------------"

if [ -f "supabase/tests/run_backend_tests.sh" ]; then
    if ./supabase/tests/run_backend_tests.sh; then
        echo -e "${GREEN}✅ Backend tests passed${NC}"
    else
        echo -e "${RED}❌ Backend tests failed${NC}"
        BACKEND_RESULT=1
    fi
else
    echo -e "${YELLOW}⚠️  Backend test script not found, skipping${NC}"
fi

echo ""

# ------------------------------
# 2. iOS Unit Tests (Xcode)
# ------------------------------
echo -e "${BLUE}📱 iOS Unit Tests (Xcode)${NC}"
echo "-------------------------"

# Find Xcode project
XCODE_PROJECT="payattentionclub-app-1.1/payattentionclub-app-1.1.xcodeproj"

if [ -d "$XCODE_PROJECT" ]; then
    echo "Building and testing..."
    
    # Run xcodebuild test
    # Using iPhone 15 simulator, adjust if needed
    if xcodebuild test \
        -project "$XCODE_PROJECT" \
        -scheme "payattentionclub-app-1.1" \
        -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
        -only-testing:payattentionclub-app-1.1Tests \
        -quiet \
        2>&1 | tail -20; then
        echo -e "${GREEN}✅ iOS unit tests passed${NC}"
    else
        echo -e "${RED}❌ iOS unit tests failed${NC}"
        IOS_RESULT=1
    fi
else
    echo -e "${YELLOW}⚠️  Xcode project not found at $XCODE_PROJECT${NC}"
    IOS_RESULT=1
fi

echo ""

# ------------------------------
# Summary
# ------------------------------
echo "============================================"
echo "📊 Test Summary"
echo "============================================"

if [ $BACKEND_RESULT -eq 0 ]; then
    echo -e "Backend (Deno):  ${GREEN}✅ PASSED${NC}"
else
    echo -e "Backend (Deno):  ${RED}❌ FAILED${NC}"
fi

if [ $IOS_RESULT -eq 0 ]; then
    echo -e "iOS Unit Tests:  ${GREEN}✅ PASSED${NC}"
else
    echo -e "iOS Unit Tests:  ${RED}❌ FAILED${NC}"
fi

echo ""

# Exit with error if any tests failed
if [ $BACKEND_RESULT -ne 0 ] || [ $IOS_RESULT -ne 0 ]; then
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
fi

