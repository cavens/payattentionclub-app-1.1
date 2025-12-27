#!/bin/bash
# Deployment script - Runs checks, tests, and commits/pushes changes
# Usage: ./scripts/deploy.sh [commit-message]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

COMMIT_MESSAGE="${1:-feat: Update code}"

echo "=========================================="
echo "🚀 Deployment Script"
echo "=========================================="
echo ""

# Step 1: Check for secrets
echo "📋 Step 1: Checking for secrets..."
if ! ./scripts/check_secrets.sh; then
    echo "❌ Secrets check failed. Aborting deployment."
    exit 1
fi
echo "✅ Secrets check passed"
echo ""

# Step 2: Run tests
echo "📋 Step 2: Running tests..."
if ! ./scripts/run_all_tests.sh; then
    echo "⚠️  Some tests failed. Continue anyway? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "❌ Deployment aborted by user"
        exit 1
    fi
fi
echo "✅ Tests completed"
echo ""

# Step 3: Stage changes
echo "📋 Step 3: Staging changes..."
git add -A
echo "✅ Changes staged"
echo ""

# Step 4: Commit
echo "📋 Step 4: Committing changes..."
if git diff --staged --quiet; then
    echo "⚠️  No changes to commit"
else
    git commit -m "$COMMIT_MESSAGE"
    echo "✅ Changes committed"
fi
echo ""

# Step 5: Push
echo "📋 Step 5: Pushing to remote..."
git push
echo "✅ Changes pushed to remote"
echo ""

echo "=========================================="
echo "✅ Deployment complete!"
echo "=========================================="


