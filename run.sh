#!/bin/bash
set -e
pkill -x NotchApp2 2>/dev/null || true
xcodebuild -project NotchApp2.xcodeproj -scheme NotchApp2 -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -10
open "$(xcodebuild -project NotchApp2.xcodeproj -scheme NotchApp2 -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/NotchApp2.app"
echo "Running. Logs: tail -f notchapp2.log"
