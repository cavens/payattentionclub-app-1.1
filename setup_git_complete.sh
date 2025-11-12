#!/bin/bash

# Complete Git Setup Script
# This script initializes git, commits all files, and sets up the remote
# Run: ./setup_git_complete.sh

set -e  # Exit on error

cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)

echo "🚀 Starting Git Setup..." | tee git_setup.log
echo "📁 Project directory: $PROJECT_DIR" | tee -a git_setup.log
echo "" | tee -a git_setup.log

# Initialize git
if [ ! -d ".git" ]; then
    echo "📦 Initializing git repository..." | tee -a git_setup.log
    git init | tee -a git_setup.log
else
    echo "✅ Git repository already initialized" | tee -a git_setup.log
fi

# Add all files
echo "📝 Adding files to git..." | tee -a git_setup.log
git add . 2>&1 | tee -a git_setup.log

# Check if there are changes to commit
if git diff --staged --quiet 2>/dev/null; then
    echo "⚠️  No changes to commit (everything is already committed)" | tee -a git_setup.log
    echo "📋 Current commit:" | tee -a git_setup.log
    git log --oneline -1 | tee -a git_setup.log
else
    echo "💾 Creating initial commit..." | tee -a git_setup.log
    git commit -m "Initial commit: Working app with Monitor Extension and App Group data sharing

- Full app flow: Loading → Setup → ScreenTimeAccess → Authorization → Monitor
- MonitoringManager successfully starts monitoring with 6 threshold events
- DeviceActivityMonitorExtension receives threshold events and writes to App Group
- MonitorView displays real usage data from App Group
- Comprehensive MARKERS logging throughout
- All core functionality working" 2>&1 | tee -a git_setup.log
fi

# Set main branch
echo "🌿 Setting main branch..." | tee -a git_setup.log
git branch -M main 2>&1 | tee -a git_setup.log || echo "Already on main branch" | tee -a git_setup.log

# Add remote
if ! git remote get-url origin &> /dev/null; then
    echo "🔗 Adding remote origin..." | tee -a git_setup.log
    git remote add origin https://github.com/cavens/payattentionclub-app-1.1.git 2>&1 | tee -a git_setup.log
else
    echo "✅ Remote origin already configured" | tee -a git_setup.log
    git remote set-url origin https://github.com/cavens/payattentionclub-app-1.1.git 2>&1 | tee -a git_setup.log
fi

# Create tag
echo "🏷️  Creating tag for this working version..." | tee -a git_setup.log
git tag -a v1.0-working -m "Working version: Monitor Extension + App Group data sharing" 2>&1 | tee -a git_setup.log || echo "Tag may already exist" | tee -a git_setup.log

# Show status
echo "" | tee -a git_setup.log
echo "📊 Git Status:" | tee -a git_setup.log
git status --short | tee -a git_setup.log

echo "" | tee -a git_setup.log
echo "📋 Recent commits:" | tee -a git_setup.log
git log --oneline -3 | tee -a git_setup.log

echo "" | tee -a git_setup.log
echo "🔗 Remotes:" | tee -a git_setup.log
git remote -v | tee -a git_setup.log

echo "" | tee -a git_setup.log
echo "✅ Git setup complete!" | tee -a git_setup.log
echo "" | tee -a git_setup.log
echo "📤 To push to GitHub, run:" | tee -a git_setup.log
echo "   git push -u origin main" | tee -a git_setup.log
echo "   git push origin v1.0-working" | tee -a git_setup.log
echo "" | tee -a git_setup.log
echo "📄 Full log saved to: git_setup.log" | tee -a git_setup.log


