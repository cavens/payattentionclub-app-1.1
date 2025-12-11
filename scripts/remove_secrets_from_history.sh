#!/bin/bash
# ==============================================================================
# Remove Secrets from Git History
# ==============================================================================
# This script removes exposed secrets from git history using git filter-branch
# 
# WARNING: This rewrites git history. You'll need to force push.
# Make sure all collaborators are aware before running this!
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "⚠️  WARNING: This will rewrite git history!"
echo "   All exposed secrets will be removed from commit history."
echo "   You'll need to force push after this completes."
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Removing secrets from git history..."
echo ""

# List of secrets to remove (JWT tokens and keys)
SECRETS=(
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF1cXVqYnBwb3l0a2VxZHNncmJsIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTQ1Nzg5NiwiZXhwIjoyMDgxMDMzODk2fQ.ZswLxpQlRnOUITjuK1WXdz-bL4A1pRGR0OxqX_A4TBI"
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZGZ0dmNydHJzbmVmaHByZWJqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzA0NzQ2NSwiZXhwIjoyMDc4NjIzNDY1fQ.l-qljQAkfgioPGv5gATTosBtA70oA_c_DZWXFuZaI44"
)

# Create a filter script
FILTER_SCRIPT=$(mktemp)
cat > "$FILTER_SCRIPT" <<'EOF'
#!/bin/bash
# Remove secrets from file content
for secret in "$@"; do
    sed -i '' "s|$secret|[REDACTED]|g" "$FILTER_BRANCH_SQUELCH_WARNING"
done
EOF

chmod +x "$FILTER_SCRIPT"

# Use git filter-repo (preferred) or git filter-branch
if command -v git-filter-repo >/dev/null 2>&1; then
    echo "Using git-filter-repo..."
    for secret in "${SECRETS[@]}"; do
        git filter-repo --replace-text <(echo "$secret==>[REDACTED]") --force
    done
else
    echo "Using git filter-branch (slower but works without git-filter-repo)..."
    git filter-branch --force --index-filter \
        "git rm --cached --ignore-unmatch -r . && git reset --hard" \
        --prune-empty --tag-name-filter cat -- --all
    
    # Remove secrets from all commits
    for secret in "${SECRETS[@]}"; do
        git filter-branch --force --tree-filter \
            "find . -type f -exec sed -i '' 's|$secret|[REDACTED]|g' {} +" \
            --prune-empty --tag-name-filter cat -- --all
    done
fi

rm -f "$FILTER_SCRIPT"

echo ""
echo "✅ Secrets removed from git history!"
echo ""
echo "⚠️  IMPORTANT NEXT STEPS:"
echo ""
echo "1. Force push to remote (this rewrites history):"
echo "   git push origin --force --all"
echo "   git push origin --force --tags"
echo ""
echo "2. ROTATE THE EXPOSED KEYS in Supabase:"
echo "   - Go to Supabase Dashboard → Settings → API"
echo "   - Regenerate service_role keys for both staging and production"
echo "   - Update your .env file with new keys"
echo ""
echo "3. Update any services using these keys"
echo ""
echo "4. Notify all collaborators to:"
echo "   git fetch origin"
echo "   git reset --hard origin/main"

