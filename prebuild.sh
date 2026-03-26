#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="$REPO_ROOT/runtime"
DEST_ROOT="${1:-}"

if [ -z "$DEST_ROOT" ]; then
  if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    echo "Usage: prebuild.sh <destination-root>" >&2
    exit 1
  fi
  DEST_ROOT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/WidgetRuntime"
fi

rm -rf "$DEST_ROOT"
mkdir -p "$DEST_ROOT/scripts" "$DEST_ROOT/widgets" "$DEST_ROOT/node/bin"

cp "$RUNTIME_ROOT/runtime-worker.mjs" "$DEST_ROOT/scripts/runtime-worker.mjs"
cp "$RUNTIME_ROOT/.build/tools/node/bin/node" "$DEST_ROOT/node/bin/node"
