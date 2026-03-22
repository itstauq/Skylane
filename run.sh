#!/bin/bash
set -e
pkill -x NotchApp 2>/dev/null || true
xcodebuild -project NotchApp.xcodeproj -scheme NotchApp -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -10
open "$(xcodebuild -project NotchApp.xcodeproj -scheme NotchApp -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/NotchApp.app"
echo "Running. Logs: tail -f notchapp.log"
