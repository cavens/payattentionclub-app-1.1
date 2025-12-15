#!/bin/bash
# ==============================================================================
# Secrets Safety Check
# ==============================================================================
# Scans all tracked files in git for exposed secrets before committing.
# 
# Usage:
#   ./scripts/check_secrets.sh
#
# Exit codes:
#   0 = No secrets found (safe to commit)
#   1 = Secrets found (DO NOT COMMIT)
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo ""
echo "🔒 Secrets Safety Check"
echo "======================"
echo ""

# Track if any secrets are found
SECRETS_FOUND=0

# Patterns to check for secrets
# Format: "pattern_name|regex_pattern"
PATTERNS=(
    "stripe_live_key|sk_live_[a-zA-Z0-9]{24,}"
    "stripe_test_key|sk_test_[a-zA-Z0-9]{24,}"
    "stripe_webhook_secret|whsec_[a-zA-Z0-9]{32,}"
    "supabase_project_token|sbp_[a-zA-Z0-9]{32,}"
    "supabase_service_role_key|eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"
)

# Files that are allowed to have public keys (anon keys are safe)
ALLOWED_FILES=(
    "Config.swift"
    "EXTENSION_NETWORK_REPORTING_PLAN.md"
)

# Get all tracked files (exclude binary files and .env)
TRACKED_FILES=$(git ls-files | grep -v -E '\.(png|jpg|jpeg|gif|ico|pdf|zip|tar|gz|xcarchive|ipa|DS_Store)$' | grep -v '\.env$' | grep -v '\.p8$')

if [ -z "$TRACKED_FILES" ]; then
    echo -e "${YELLOW}⚠️  No tracked files found${NC}"
    exit 0
fi

echo "Scanning $(echo "$TRACKED_FILES" | wc -l | tr -d ' ') files..."
echo ""

# Check each pattern
for pattern_info in "${PATTERNS[@]}"; do
    PATTERN_NAME=$(echo "$pattern_info" | cut -d'|' -f1)
    PATTERN=$(echo "$pattern_info" | cut -d'|' -f2)
    
    # Search for pattern in tracked files
    MATCHES=$(echo "$TRACKED_FILES" | xargs grep -l -E "$PATTERN" 2>/dev/null || true)
    
    if [ -n "$MATCHES" ]; then
        # Filter out allowed files and check for service_role (not anon)
        FILTERED_MATCHES=""
        while IFS= read -r file; do
            # Check if file is in allowed list
            IS_ALLOWED=0
            for allowed in "${ALLOWED_FILES[@]}"; do
                if echo "$file" | grep -q "$allowed$"; then
                    # For JWT tokens in allowed files, check if it's service_role (secret) or anon (public)
                    if echo "$PATTERN_NAME" | grep -q "jwt_token\|supabase_service_role_key"; then
                        # Decode JWT to check role (basic check - look for "service_role" in payload)
                        if grep -q "service_role" "$file" 2>/dev/null; then
                            # This is a service role key - flag it!
                            FILTERED_MATCHES="$FILTERED_MATCHES$file\n"
                        fi
                        # If it's anon role, skip it (safe to commit)
                    else
                        # For other patterns in allowed files, still check
                        FILTERED_MATCHES="$FILTERED_MATCHES$file\n"
                    fi
                    IS_ALLOWED=1
                    break
                fi
            done
            
            if [ $IS_ALLOWED -eq 0 ]; then
                # File not in allowed list - flag it
                FILTERED_MATCHES="$FILTERED_MATCHES$file\n"
            fi
        done <<< "$MATCHES"
        
        if [ -n "$FILTERED_MATCHES" ]; then
            SECRETS_FOUND=1
            echo -e "${RED}❌ Found $PATTERN_NAME in:${NC}"
            echo -e "$FILTERED_MATCHES" | while read -r file; do
                [ -n "$file" ] && echo -e "   ${RED}→${NC} $file"
                [ -n "$file" ] && echo "$TRACKED_FILES" | grep -q "^$file$" && \
                    grep -n -E "$PATTERN" "$file" 2>/dev/null | head -3 | sed 's/^/      /' || true
            done
            echo ""
        fi
    fi
done

# Hardcoded secrets check disabled - too many false positives
# Focus on specific secret patterns above (Stripe keys, webhook secrets, etc.)

# Summary
echo "======================"
if [ $SECRETS_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ No secrets found. Safe to commit!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ SECRETS FOUND! DO NOT COMMIT!${NC}"
    echo ""
    echo "Please:"
    echo "  1. Remove secrets from files"
    echo "  2. Use .env file or environment variables instead"
    echo "  3. If secrets were already committed, rotate them immediately"
    echo ""
    exit 1
fi

