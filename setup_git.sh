#!/bin/bash

# Script to initialize git and push to GitHub
# Run this from the project root: ./setup_git.sh

set -e  # Exit on error

echo "🚀 Setting up Git repository..."

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Git is not installed. Please install Git first."
    exit 1
fi

# Navigate to project root
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
echo "📁 Project directory: $PROJECT_DIR"

# Initialize git if not already initialized
if [ ! -d ".git" ]; then
    echo "📦 Initializing git repository..."
    git init
else
    echo "✅ Git repository already initialized"
fi

# Add all files
echo "📝 Adding files to git..."
git add .

# Check if there are changes to commit
if git diff --staged --quiet; then
    echo "⚠️  No changes to commit (everything is already committed)"
else
    echo "💾 Creating initial commit..."
    git commit -m "Initial commit: Working app with Monitor Extension and App Group data sharing

- Full app flow: Loading → Setup → ScreenTimeAccess → Authorization → Monitor
- MonitoringManager successfully starts monitoring with 6 threshold events
- DeviceActivityMonitorExtension receives threshold events and writes to App Group
- MonitorView displays real usage data from App Group
- Comprehensive MARKERS logging throughout
- All core functionality working"
fi

# Set main branch
echo "🌿 Setting main branch..."
git branch -M main 2>/dev/null || echo "Already on main branch"

# Add remote if not exists
if ! git remote get-url origin &> /dev/null; then
    echo "🔗 Adding remote origin..."
    git remote add origin https://github.com/cavens/payattentionclub-app-1.1.git
else
    echo "✅ Remote origin already configured"
    git remote set-url origin https://github.com/cavens/payattentionclub-app-1.1.git
fi

# Create a tag for this working version
echo "🏷️  Creating tag for this working version..."
git tag -a v1.0-working -m "Working version: Monitor Extension + App Group data sharing" 2>/dev/null || echo "Tag already exists"

# Show status
echo ""
echo "📊 Current status:"
git status --short

echo ""
echo "📋 Recent commits:"
git log --oneline -3

echo ""
echo "✅ Git setup complete!"
echo ""
echo "📤 To push to GitHub, run:"
echo "   git push -u origin main"
echo "   git push origin v1.0-working"
echo ""
echo "💡 Or run this script again - it will show you the push commands"





