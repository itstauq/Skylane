#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$REPO_ROOT/NotchApp/AppSettingsView.swift"
COMMIT_HASH="${1:-$(git -C "$REPO_ROOT" rev-parse --short HEAD)}"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Could not find $SETTINGS_FILE" >&2
  exit 1
fi

perl -0pi -e 's/AboutInfoRow\(label: "Commit", value: "[^"]*"\)/AboutInfoRow(label: "Commit", value: "'"$COMMIT_HASH"'")/' "$SETTINGS_FILE"

echo "commit=$COMMIT_HASH"
