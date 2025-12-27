#!/bin/bash
# Check for secrets in staged files before push

set -e

echo "🔍 Checking for secrets in staged files..."

# Patterns to detect
PATTERNS=(
    "sk_live_[a-zA-Z0-9]{24,}"      # Stripe live key
    "sk_test_[a-zA-Z0-9]{24,}"      # Stripe test key
    "whsec_[a-zA-Z0-9]{32,}"        # Stripe webhook secret
    "eyJ[A-Za-z0-9_-]{100,}"        # JWT tokens (service role keys)
    "sbp_[a-zA-Z0-9]{32,}"          # Supabase project tokens
)

# Get staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo "✅ No staged files to check"
    exit 0
fi

FOUND_SECRETS=false

for file in $STAGED_FILES; do
    # Skip .env files (they're gitignored anyway)
    if [[ "$file" == *".env"* ]]; then
        continue
    fi
    
    for pattern in "${PATTERNS[@]}"; do
        if git diff --cached "$file" | grep -qE "$pattern"; then
            echo "❌ SECRET DETECTED in $file:"
            echo "   Pattern: $pattern"
            FOUND_SECRETS=true
        fi
    done
done

if [ "$FOUND_SECRETS" = true ]; then
    echo ""
    echo "🚨 BLOCKED: Secrets detected in staged files!"
    echo "   Remove secrets before pushing to remote."
    echo "   See docs/KNOWN_ISSUES.md for details."
    exit 1
fi

echo "✅ No secrets detected"
exit 0


