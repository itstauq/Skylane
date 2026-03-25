#!/bin/bash
set -euo pipefail

WIDGET_RUNTIME_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="${1:-}"

if [ -z "$DEST_ROOT" ]; then
  if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    echo "Usage: prepare-bundled-runtime.sh <destination-root>" >&2
    exit 1
  fi
  DEST_ROOT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/WidgetRuntime"
fi

for widget_dir in "$WIDGET_RUNTIME_ROOT"/widgets/*; do
  if [ ! -d "$widget_dir" ]; then
    continue
  fi

  (
    cd "$widget_dir"
    "$WIDGET_RUNTIME_ROOT/scripts/notch-widget" build
  )
done

rm -rf "$DEST_ROOT"
mkdir -p "$DEST_ROOT/scripts" "$DEST_ROOT/widgets" "$DEST_ROOT/node/bin"

cp "$WIDGET_RUNTIME_ROOT/scripts/widget-helper.mjs" "$DEST_ROOT/scripts/widget-helper.mjs"
cp "$WIDGET_RUNTIME_ROOT/.build/tools/node/bin/node" "$DEST_ROOT/node/bin/node"

for widget_dir in "$WIDGET_RUNTIME_ROOT"/widgets/*; do
  if [ ! -d "$widget_dir" ]; then
    continue
  fi
  widget_name="$(basename "$widget_dir")"
  cp -R "$widget_dir" "$DEST_ROOT/widgets/$widget_name"
done
