#!/bin/bash
# Test Production Frontend with Staging Backend
#
# This script helps you build the current production iOS app version
# but connect it to the staging backend for compatibility testing.
#
# Usage:
#   ./scripts/test_production_frontend_with_staging.sh
#
# This is a MANDATORY step before deploying backend to production.

set -e

echo "🧪 Test Production Frontend with Staging Backend"
echo "================================================"
echo ""

# Get current production version from git tags or Info.plist
PROD_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
echo "📱 Current Production Version: $PROD_VERSION"
echo ""

# Check if staging override scheme exists
SCHEME_NAME="Release (Staging)"
echo "🔍 Checking for staging override configuration..."
echo ""

# Instructions for setting up the override
echo "📋 SETUP INSTRUCTIONS:"
echo "----------------------"
echo ""
echo "1. Open Xcode"
echo "2. Go to: Product → Scheme → Manage Schemes"
echo "3. Duplicate 'payattentionclub-app-1.1' scheme"
echo "4. Rename it to: 'Release (Staging)'"
echo "5. Edit the scheme → Run → Arguments → Environment Variables"
echo "6. Add: USE_STAGING = true"
echo "7. Close and save"
echo ""
echo "OR: Temporarily modify Config.swift:"
echo "   Change: static let current: Environment = .production"
echo "   To:     static let current: Environment = .staging"
echo "   (Remember to revert before App Store submission!)"
echo ""

read -p "Have you set up the staging override? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please set up the staging override first, then run this script again."
    exit 1
fi

echo ""
echo "✅ Staging override configured"
echo ""

# Build instructions
echo "📦 BUILD INSTRUCTIONS:"
echo "----------------------"
echo ""
echo "1. In Xcode, select scheme: 'Release (Staging)' (or your override)"
echo "2. Product → Archive"
echo "3. Distribute App → Development"
echo "4. Install on your test device"
echo ""

read -p "Have you built and installed the app on your device? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Please build and install the app first, then run this script again."
    exit 1
fi

echo ""
echo "✅ App installed on device"
echo ""

# Testing checklist
echo "🧪 MANUAL TESTING CHECKLIST:"
echo "============================="
echo ""
echo "Test the following critical flows with PRODUCTION frontend ($PROD_VERSION)"
echo "connected to STAGING backend:"
echo ""
echo "Authentication:"
echo "  [ ] Sign in with Apple works"
echo "  [ ] User can complete onboarding"
echo ""
echo "Commitment Creation:"
echo "  [ ] Can create a new commitment"
echo "  [ ] Authorization amount displays correctly"
echo "  [ ] Payment setup works (Stripe)"
echo "  [ ] Commitment is saved successfully"
echo ""
echo "Monitoring:"
echo "  [ ] App monitoring is active"
echo "  [ ] Usage data is tracked"
echo "  [ ] Can view current usage"
echo ""
echo "Backend Compatibility:"
echo "  [ ] All RPC calls succeed"
echo "  [ ] No version mismatch errors"
echo "  [ ] Data syncs correctly"
echo ""
echo "Critical User Flows:"
echo "  [ ] Complete commitment flow end-to-end"
echo "  [ ] View dashboard/status"
echo "  [ ] Check billing status"
echo ""

read -p "Have you completed all checklist items? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "❌ Please complete all testing checklist items before proceeding."
    echo "   This is a MANDATORY step before deploying backend to production."
    exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "🎉 Production frontend ($PROD_VERSION) is compatible with staging backend."
echo "   You can now proceed with deploying backend to production."
echo ""

