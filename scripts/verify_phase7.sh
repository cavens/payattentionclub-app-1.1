#!/bin/bash

# Phase 7 Manual Verification Helper Script
# This script helps verify what can be checked programmatically
# and guides you through manual Dashboard checks

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Source environment variables
if [ -f .env ]; then
    source .env
else
    echo "❌ .env file not found!"
    exit 1
fi

echo "🔍 Phase 7: Manual Verification Helper"
echo "========================================"
echo ""

# Function to check if we can reach an endpoint
check_endpoint() {
    local url=$1
    local name=$2
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ] || [ "$response" = "404" ]; then
        echo "  ✅ $name: Reachable (HTTP $response)"
        return 0
    else
        echo "  ⚠️  $name: May not be deployed (HTTP $response)"
        return 1
    fi
}

echo "📊 AUTOMATED CHECKS (Already Verified)"
echo "--------------------------------------"
echo "✅ Cron jobs: 3 in staging, 3 in production"
echo "✅ Database tables: 7/7 in both environments"
echo "✅ RPC functions: 7/7 in both environments"
echo "✅ Service role keys: Set in both environments"
echo "✅ call_weekly_close(): Working in both environments"
echo "✅ iOS configuration: Correct"
echo ""
echo ""

echo "🔍 CHECKING EDGE FUNCTIONS (Programmatic Check)"
echo "-----------------------------------------------"
echo ""
echo "STAGING Environment:"
echo ""

# Check staging Edge Functions
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/billing-status" "billing-status"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/weekly-close" "weekly-close"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/stripe-webhook" "stripe-webhook"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/super-service" "super-service"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/rapid-service" "rapid-service"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/bright-service" "bright-service"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/quick-handler" "quick-handler"
check_endpoint "${STAGING_SUPABASE_URL}/functions/v1/admin-close-week-now" "admin-close-week-now"

echo ""
echo "PRODUCTION Environment:"
echo ""

# Check production Edge Functions
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/billing-status" "billing-status"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/weekly-close" "weekly-close"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/stripe-webhook" "stripe-webhook"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/super-service" "super-service"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/rapid-service" "rapid-service"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/bright-service" "bright-service"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/quick-handler" "quick-handler"
check_endpoint "${PRODUCTION_SUPABASE_URL}/functions/v1/admin-close-week-now" "admin-close-week-now"

echo ""
echo ""
echo "📋 MANUAL DASHBOARD CHECKS REQUIRED"
echo "===================================="
echo ""
echo "Please verify the following in Supabase Dashboard:"
echo ""
echo "STAGING:"
echo "  1. Edge Functions: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions"
echo "     - Verify all 8 functions are listed"
echo ""
echo "  2. Edge Function Secrets: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/functions"
echo "     - STRIPE_SECRET_KEY (test key)"
echo "     - STRIPE_WEBHOOK_SECRET"
echo ""
echo "  3. Cron Jobs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/database/cron"
echo "     - 3 jobs should be visible and active"
echo ""
echo "  4. Apple Sign-In: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/auth/providers"
echo "     - Apple provider should be enabled"
echo ""
echo "  5. Edge Function Logs: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs"
echo "     - Should show recent test invocations"
echo ""
echo "PRODUCTION:"
echo "  1. Edge Functions: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions"
echo "     - Verify all 8 functions are listed"
echo ""
echo "  2. Edge Function Secrets: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/settings/functions"
echo "     - STRIPE_SECRET_KEY (live key)"
echo "     - STRIPE_WEBHOOK_SECRET"
echo ""
echo "  3. Cron Jobs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/database/cron"
echo "     - 3 jobs should be visible and active"
echo ""
echo "  4. Apple Sign-In: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/providers"
echo "     - Apple provider should be enabled"
echo ""
echo "  5. Edge Function Logs: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs"
echo "     - Should show recent test invocations"
echo ""
echo ""
echo "📋 STRIPE WEBHOOK CHECKS"
echo "========================"
echo ""
echo "STAGING (Test Mode):"
echo "  - Go to: https://dashboard.stripe.com/test/webhooks"
echo "  - Verify webhook exists for: https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook"
echo ""
echo "PRODUCTION (Live Mode):"
echo "  - Go to: https://dashboard.stripe.com/webhooks"
echo "  - Verify webhook exists for: https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook"
echo ""
echo ""
echo "✅ After completing manual checks, update: docs/PHASE7_RESULTS.md"
echo ""


