#!/bin/bash

# Script to copy files to Xcode project directory
# After running this, drag and drop files into Xcode to add them to the project

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
XCODE_PROJECT_DIR="$SCRIPT_DIR/payattentionclub-app-1.1/payattentionclub-app-1.1"

echo "📁 Copying files to Xcode project directory..."
echo "   Target: $XCODE_PROJECT_DIR"

# Create directories if they don't exist
mkdir -p "$XCODE_PROJECT_DIR/Models"
mkdir -p "$XCODE_PROJECT_DIR/Views"
mkdir -p "$XCODE_PROJECT_DIR/Utilities"

# Copy main app file (replace existing)
echo "📄 Copying main app file..."
cp "$SCRIPT_DIR/payattentionclub_app_1_1App.swift" "$XCODE_PROJECT_DIR/payattentionclub-app-1.1/payattentionclub_app_1_1App.swift"

# Copy Models
echo "📄 Copying Models..."
cp "$SCRIPT_DIR/Models/AppModel.swift" "$XCODE_PROJECT_DIR/Models/AppModel.swift"

# Copy Views
echo "📄 Copying Views..."
cp "$SCRIPT_DIR/Views/"*.swift "$XCODE_PROJECT_DIR/Views/"

# Copy Utilities
echo "📄 Copying Utilities..."
cp "$SCRIPT_DIR/Utilities/"*.swift "$XCODE_PROJECT_DIR/Utilities/"

# Copy Monitor Extension (replace existing)
echo "📄 Copying Monitor Extension..."
cp "$SCRIPT_DIR/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift" \
   "$XCODE_PROJECT_DIR/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift"

echo ""
echo "✅ Files copied successfully!"
echo ""
echo "📋 Next steps:"
echo "   1. Open Xcode project"
echo "   2. In Project Navigator, right-click on 'payattentionclub-app-1.1' folder"
echo "   3. Select 'Add Files to payattentionclub-app-1.1...'"
echo "   4. Navigate to: $XCODE_PROJECT_DIR"
echo "   5. Select these folders: Models, Views, Utilities"
echo "   6. Check 'Copy items if needed' (should be unchecked since files are already there)"
echo "   7. Check 'Create groups' (not folder references)"
echo "   8. Check the correct target: 'payattentionclub-app-1.1'"
echo "   9. Click 'Add'"
echo ""
echo "   For the extension file:"
echo "   10. Right-click on 'DeviceActivityMonitorExtension' folder"
echo "   11. Select 'Add Files to DeviceActivityMonitorExtension...'"
echo "   12. Select: DeviceActivityMonitorExtension.swift"
echo "   13. Check target: 'DeviceActivityMonitorExtension'"
echo "   14. Click 'Add'"

