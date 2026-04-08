repo_root := justfile_directory()

default:
    just --list

bump-version bump_type:
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="{{ repo_root }}"
    PROJECT_FILE="$REPO_ROOT/NotchApp.xcodeproj/project.pbxproj"
    SETTINGS_FILE="$REPO_ROOT/NotchApp/AppSettingsView.swift"
    BUMP_TYPE="{{ bump_type }}"

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
    COMMIT_HASH="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
    perl -0pi -e 's/AboutInfoRow\(label: "Commit", value: "[^"]*"\)/AboutInfoRow(label: "Commit", value: "'"$COMMIT_HASH"'")/' "$SETTINGS_FILE"

    echo "version=${NEXT_VERSION}"
    echo "build=${NEXT_BUILD}"
    echo "tag=v${NEXT_VERSION}"

test:
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="{{ repo_root }}"
    BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/.build/ci}"
    DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
    SOURCE_PACKAGES_DIR="$BUILD_ROOT/SourcePackages"

    mkdir -p "$BUILD_ROOT" "$SOURCE_PACKAGES_DIR"

    echo "Bootstrapping bundled widget toolchain..."
    "$REPO_ROOT/runtime/runtime-launcher" bootstrap
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

[arg("no_build", long="no-build", value="true", help="Skip the build step and relaunch the app")]
dev no_build='false':
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="{{ repo_root }}"
    DERIVED_DATA_PATH="$REPO_ROOT/.build/DerivedData"
    APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/NotchApp.app"

    if [ "{{ no_build }}" != "true" ]; then
      xcodebuild \
        -project "$REPO_ROOT/NotchApp.xcodeproj" \
        -scheme NotchApp \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -10
    fi

    OLD_PIDS="$(pgrep -x NotchApp 2>/dev/null || true)"
    if [ -n "$OLD_PIDS" ]; then
      pkill -x NotchApp 2>/dev/null || true

      for pid in $OLD_PIDS; do
        while kill -0 "$pid" 2>/dev/null; do
          sleep 0.5
        done
      done
    fi

    open "$APP_PATH"
    echo "Running. Logs: tail -f notchapp.log"

[arg("sign", long="sign", value="true", help="Sign the release archive for distribution")]
package sign='false':
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="{{ repo_root }}"

    if [ "{{ sign }}" = "true" ] && [ -z "${APPLE_TEAM_ID:-}" ]; then
      echo "APPLE_TEAM_ID is required when using --sign" >&2
      exit 1
    fi

    mkdir -p "$REPO_ROOT/.build/release/SourcePackages"
    "$REPO_ROOT/runtime/runtime-launcher" bootstrap

    if [ "{{ sign }}" = "true" ]; then
      xcodebuild archive \
        -project "$REPO_ROOT/NotchApp.xcodeproj" \
        -scheme NotchApp \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$REPO_ROOT/.build/release/NotchApp.xcarchive" \
        -derivedDataPath "$REPO_ROOT/.build/release/DerivedData" \
        -clonedSourcePackagesDirPath "$REPO_ROOT/.build/release/SourcePackages" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
        CODE_SIGN_IDENTITY="Developer ID Application" \
        PROVISIONING_PROFILE_SPECIFIER="" \
        PROVISIONING_PROFILE=""
    else
      xcodebuild archive \
        -project "$REPO_ROOT/NotchApp.xcodeproj" \
        -scheme NotchApp \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$REPO_ROOT/.build/release/NotchApp.xcarchive" \
        -derivedDataPath "$REPO_ROOT/.build/release/DerivedData" \
        -clonedSourcePackagesDirPath "$REPO_ROOT/.build/release/SourcePackages" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO
    fi

    APP_PATH="$REPO_ROOT/.build/release/NotchApp.xcarchive/Products/Applications/NotchApp.app"
    FRAMEWORK_PATH="$APP_PATH/Contents/Resources/WidgetRuntime/mediaremote-adapter/MediaRemoteAdapter.framework"

    if [ "{{ sign }}" != "true" ]; then
      exit 0
    fi

    if [ ! -d "$APP_PATH" ]; then
      echo "Archived app not found at $APP_PATH" >&2
      exit 1
    fi

    if [ -d "$FRAMEWORK_PATH" ]; then
      codesign --force --sign "Developer ID Application" --timestamp "$FRAMEWORK_PATH"
    fi

    codesign --force \
      --sign "Developer ID Application" \
      --options runtime \
      --timestamp \
      --entitlements "$REPO_ROOT/NotchApp/NotchApp.entitlements" \
      "$APP_PATH"

    codesign --verify --deep --strict --verbose=2 "$APP_PATH"

build-dmg:
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="{{ repo_root }}"
    APP_PATH="$REPO_ROOT/.build/release/NotchApp.xcarchive/Products/Applications/NotchApp.app"

    mkdir -p "$REPO_ROOT/.build/release/artifacts"
    "$REPO_ROOT/.build/release/node-global/node_modules/.bin/create-dmg" \
      --overwrite \
      "$APP_PATH" \
      "$REPO_ROOT/.build/release/artifacts"

notarize-dmg:
    #!/usr/bin/env bash
    set -euo pipefail

    REPO_ROOT="{{ repo_root }}"

    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
      echo "APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, and APPLE_TEAM_ID are required" >&2
      exit 1
    fi

    DMG_PATH="$(find "$REPO_ROOT/.build/release/artifacts" -maxdepth 1 -name '*.dmg' -print -quit)"
    if [ -z "$DMG_PATH" ]; then
      echo "DMG not found" >&2
      exit 1
    fi

    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait

    xcrun stapler staple "$DMG_PATH"
    echo "$DMG_PATH"

release-local:
    just package --sign
    just build-dmg
    just notarize-dmg
