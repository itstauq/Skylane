#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/.build/ci}"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
SOURCE_PACKAGES_DIR="$BUILD_ROOT/SourcePackages"

mkdir -p "$BUILD_ROOT" "$SOURCE_PACKAGES_DIR"

echo "Bootstrapping bundled widget toolchain..."
"$REPO_ROOT/runtime/runtime-launcher" bootstrap
NODE_BIN="$REPO_ROOT/runtime/.build/tools/node/bin/node"
NPM_BIN="$REPO_ROOT/runtime/.build/tools/node/bin/npm"

echo "Installing runtime dependencies..."
"$NPM_BIN" ci --prefix "$REPO_ROOT/runtime"

echo "Installing SDK dependencies..."
"$NPM_BIN" ci --prefix "$REPO_ROOT/sdk"

echo "Running runtime tests..."
"$NPM_BIN" test --prefix "$REPO_ROOT/runtime"

echo "Running SDK tests..."
"$NPM_BIN" test --prefix "$REPO_ROOT/sdk"

echo "Running macOS unit tests..."
xcodebuild test \
  -project "$REPO_ROOT/NotchApp.xcodeproj" \
  -scheme NotchAppTests \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
