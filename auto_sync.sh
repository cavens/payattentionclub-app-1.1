#!/bin/bash

# Auto-sync script: Watches for file changes and automatically copies to Xcode project
# Run this script in the background: ./auto_sync.sh &
# Or run in a separate terminal window

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
XCODE_PROJECT_DIR="$SCRIPT_DIR/payattentionclub-app-1.1/payattentionclub-app-1.1"

echo "🔄 Starting auto-sync..."
echo "   Watching: $SCRIPT_DIR"
echo "   Target: $XCODE_PROJECT_DIR"
echo ""
echo "   Press Ctrl+C to stop"
echo ""

# Function to sync files
sync_files() {
    echo "📦 Syncing files... $(date '+%H:%M:%S')"
    
    # Copy main app file
    if [ -f "$SCRIPT_DIR/payattentionclub_app_1_1App.swift" ]; then
        cp "$SCRIPT_DIR/payattentionclub_app_1_1App.swift" "$XCODE_PROJECT_DIR/payattentionclub_app_1_1App.swift" 2>/dev/null
    fi
    
    # Copy Models
    if [ -d "$SCRIPT_DIR/Models" ]; then
        mkdir -p "$XCODE_PROJECT_DIR/Models"
        cp "$SCRIPT_DIR/Models/"*.swift "$XCODE_PROJECT_DIR/Models/" 2>/dev/null
    fi
    
    # Copy Views
    if [ -d "$SCRIPT_DIR/Views" ]; then
        mkdir -p "$XCODE_PROJECT_DIR/Views"
        cp "$SCRIPT_DIR/Views/"*.swift "$XCODE_PROJECT_DIR/Views/" 2>/dev/null
    fi
    
    # Copy Utilities
    if [ -d "$SCRIPT_DIR/Utilities" ]; then
        mkdir -p "$XCODE_PROJECT_DIR/Utilities"
        cp "$SCRIPT_DIR/Utilities/"*.swift "$XCODE_PROJECT_DIR/Utilities/" 2>/dev/null
    fi
    
    # Copy Monitor Extension
    if [ -f "$SCRIPT_DIR/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift" ]; then
        mkdir -p "$XCODE_PROJECT_DIR/../DeviceActivityMonitorExtension"
        cp "$SCRIPT_DIR/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift" \
           "$XCODE_PROJECT_DIR/../DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift" 2>/dev/null
    fi
}

# Initial sync
sync_files

# Check if fswatch is available (macOS file watcher)
if command -v fswatch &> /dev/null; then
    echo "✅ Using fswatch for file watching"
    echo ""
    
    # Watch for changes and sync
    fswatch -o "$SCRIPT_DIR" --exclude='.*' --include='\.swift$' | while read f; do
        sync_files
    done
else
    echo "⚠️  fswatch not found. Using polling mode (checks every 2 seconds)"
    echo "   Install fswatch for better performance: brew install fswatch"
    echo ""
    
    # Polling mode (fallback)
    while true; do
        sleep 2
        sync_files
    done
fi





