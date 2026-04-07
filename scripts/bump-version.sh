#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <major|minor|patch>" >&2
  exit 1
fi

BUMP_TYPE="$1"
PROJECT_FILE="$(cd "$(dirname "$0")/.." && pwd)/NotchApp.xcodeproj/project.pbxproj"

case "$BUMP_TYPE" in
  major|minor|patch)
    ;;
  *)
    echo "Unknown bump type: $BUMP_TYPE" >&2
    exit 1
    ;;
esac

CURRENT_VERSION="$(perl -ne 'if (/MARKETING_VERSION = ([0-9]+(?:\.[0-9]+){1,2});/) { print $1; exit }' "$PROJECT_FILE")"
CURRENT_BUILD="$(perl -ne 'if (/CURRENT_PROJECT_VERSION = ([0-9]+);/) { print $1; exit }' "$PROJECT_FILE")"

if [ -z "$CURRENT_VERSION" ] || [ -z "$CURRENT_BUILD" ]; then
  echo "Could not read current version/build from $PROJECT_FILE" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$(printf '%s' "$CURRENT_VERSION" | awk -F. '{ if (NF == 2) { printf "%s.%s.0", $1, $2 } else { printf "%s.%s.%s", $1, $2, $3 } }')"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEXT_BUILD="$((CURRENT_BUILD + 1))"

perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+){1,2};/MARKETING_VERSION = ${NEXT_VERSION};/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEXT_BUILD};/g" "$PROJECT_FILE"

echo "version=${NEXT_VERSION}"
echo "build=${NEXT_BUILD}"
echo "tag=v${NEXT_VERSION}"
