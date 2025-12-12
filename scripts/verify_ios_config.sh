#!/bin/bash
# ==============================================================================
# iOS Configuration Verification Script
# ==============================================================================
# Verifies that Config.swift has the correct staging and production values
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/Config.swift"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "🔍 iOS Configuration Verification"
echo "================================="
echo ""

# Check if Config.swift exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Config.swift not found at: $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found Config.swift"
echo ""

# Expected values
EXPECTED_STAGING_URL="https://auqujbppoytkeqdsgrbl.supabase.co"
EXPECTED_PRODUCTION_URL="https://whdftvcrtrsnefhprebj.supabase.co"
EXPECTED_STAGING_PUBLISHABLE_KEY_START="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF1cXVqYnBwb3l0a2VxZHNncmJs"
EXPECTED_PRODUCTION_PUBLISHABLE_KEY_START="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZGZ0dmNydHJzbmVmaHByZWJq"

# Extract values from Config.swift
STAGING_URL=$(grep -A 1 "stagingProjectURL" "$CONFIG_FILE" | grep "https://" | sed 's/.*"\(.*\)".*/\1/' | head -1)
PRODUCTION_URL=$(grep -A 1 "productionProjectURL" "$CONFIG_FILE" | grep "https://" | sed 's/.*"\(.*\)".*/\1/' | head -1)
STAGING_PUBLISHABLE_KEY=$(grep -A 1 "stagingPublishableKey" "$CONFIG_FILE" | grep "eyJ" | sed 's/.*"\(.*\)".*/\1/' | head -1)
PRODUCTION_PUBLISHABLE_KEY=$(grep -A 1 "productionPublishableKey" "$CONFIG_FILE" | grep "eyJ" | sed 's/.*"\(.*\)".*/\1/' | head -1)

# Verify staging URL
echo "Checking Staging Configuration..."
if [ "$STAGING_URL" = "$EXPECTED_STAGING_URL" ]; then
    echo -e "  ${GREEN}✓${NC} Staging URL: $STAGING_URL"
else
    echo -e "  ${RED}❌${NC} Staging URL mismatch!"
    echo "     Expected: $EXPECTED_STAGING_URL"
    echo "     Found:    $STAGING_URL"
fi

# Verify staging publishable key (check first part)
if echo "$STAGING_PUBLISHABLE_KEY" | grep -q "$EXPECTED_STAGING_PUBLISHABLE_KEY_START"; then
    echo -e "  ${GREEN}✓${NC} Staging Publishable Key: ${STAGING_PUBLISHABLE_KEY:0:50}..."
else
    echo -e "  ${RED}❌${NC} Staging Publishable Key mismatch!"
fi

echo ""

# Verify production URL
echo "Checking Production Configuration..."
if [ "$PRODUCTION_URL" = "$EXPECTED_PRODUCTION_URL" ]; then
    echo -e "  ${GREEN}✓${NC} Production URL: $PRODUCTION_URL"
else
    echo -e "  ${RED}❌${NC} Production URL mismatch!"
    echo "     Expected: $EXPECTED_PRODUCTION_URL"
    echo "     Found:    $PRODUCTION_URL"
fi

# Verify production publishable key (check first part)
if echo "$PRODUCTION_PUBLISHABLE_KEY" | grep -q "$EXPECTED_PRODUCTION_PUBLISHABLE_KEY_START"; then
    echo -e "  ${GREEN}✓${NC} Production Publishable Key: ${PRODUCTION_PUBLISHABLE_KEY:0:50}..."
else
    echo -e "  ${RED}❌${NC} Production Publishable Key mismatch!"
fi

echo ""

# Check environment switching logic
echo "Checking Environment Switching Logic..."
if grep -q "#if DEBUG" "$CONFIG_FILE" && grep -q "return .staging" "$CONFIG_FILE"; then
    echo -e "  ${GREEN}✓${NC} DEBUG builds → Staging"
else
    echo -e "  ${YELLOW}⚠️${NC}  Could not verify DEBUG → Staging logic"
fi

if grep -q "#else" "$CONFIG_FILE" && grep -q "return .production" "$CONFIG_FILE"; then
    echo -e "  ${GREEN}✓${NC} RELEASE builds → Production"
else
    echo -e "  ${YELLOW}⚠️${NC}  Could not verify RELEASE → Production logic"
fi

echo ""
echo "================================="
echo "✅ Verification complete!"
echo ""
echo "Next steps:"
echo "  1. Build and run in Xcode (Debug mode)"
echo "  2. Open Dev Menu (triple-tap countdown logo)"
echo "  3. Verify Environment shows 'STAGING'"
echo "  4. Verify Supabase URL shows staging URL"
echo ""


