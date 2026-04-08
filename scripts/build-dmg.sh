#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/build-dmg.sh <version>
# Example: ./scripts/build-dmg.sh 1.0.7

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
RELEASE_DIR="$BUILD_DIR/release"
STAGING_DIR="$BUILD_DIR/dmg-staging"
APP_DIR="$STAGING_DIR/Level5Island.app"
CONTENTS_DIR="$APP_DIR/Contents"
OUTPUT_DMG="$BUILD_DIR/Level5Island.dmg"

echo "==> Building Level5Island ${VERSION} (universal)"

# Build for both architectures
cd "$REPO_ROOT"
swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM_DIR="$BUILD_DIR/arm64-apple-macosx/release"
X86_DIR="$BUILD_DIR/x86_64-apple-macosx/release"

echo "==> Assembling .app bundle"

# Clean and recreate staging
rm -rf "$STAGING_DIR"
mkdir -p "$CONTENTS_DIR/MacOS"
mkdir -p "$CONTENTS_DIR/Helpers"
mkdir -p "$CONTENTS_DIR/Resources"

# Create universal binaries
lipo -create "$ARM_DIR/Level5Island" "$X86_DIR/Level5Island" \
     -output "$CONTENTS_DIR/MacOS/Level5Island"
lipo -create "$ARM_DIR/level5island-bridge" "$X86_DIR/level5island-bridge" \
     -output "$CONTENTS_DIR/Helpers/level5island-bridge"

# Write Info.plist (use the root Info.plist as base, update version)
CURRENT_VER=$(defaults read "$REPO_ROOT/Info.plist" CFBundleShortVersionString)
sed -e "s/<string>${CURRENT_VER}<\/string>/<string>${VERSION}<\/string>/g" \
    "$REPO_ROOT/Info.plist" > "$CONTENTS_DIR/Info.plist"

# Compile app icon and asset catalog
xcrun actool \
    --output-format human-readable-text \
    --notices --warnings --errors \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /dev/null \
    --compile "$CONTENTS_DIR/Resources" \
    "$REPO_ROOT/Assets.xcassets" \
    "$REPO_ROOT/AppIcon.icon"

# Copy SPM resource bundles into Contents/Resources (codesign requires nothing unsealed at app root)
for bundle in "$BUILD_DIR"/*/release/Level5Island_Level5Island.bundle; do
    if [ -e "$bundle" ]; then
        cp -R "$bundle" "$CONTENTS_DIR/Resources/"
        break
    fi
done

echo "==> App bundle assembled at $APP_DIR"

# ---------------------------------------------------------------------------
# Code signing — uses SIGNING_IDENTITY and TEAM_ID from environment.
# If SIGNING_IDENTITY is not set, falls back to ad-hoc signing (local dev).
# ---------------------------------------------------------------------------
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    echo "==> Signing with Developer ID: $SIGNING_IDENTITY"

    # Sign helper binary first
    codesign --force --options runtime \
        --sign "$SIGNING_IDENTITY" \
        "$CONTENTS_DIR/Helpers/level5island-bridge"

    # Sign the app bundle with entitlements
    codesign --deep --force --options runtime \
        --entitlements "$REPO_ROOT/Level5Island.entitlements" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_DIR"
else
    echo "==> SIGNING_IDENTITY not set, using ad-hoc signing (not notarized)"
    codesign --deep --force --sign - "$APP_DIR"
fi

echo "==> Creating DMG"

# Remove previous DMG if exists
rm -f "$OUTPUT_DMG"

create-dmg \
    --volname "Level5Island ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Level5Island.app" 175 190 \
    --hide-extension "Level5Island.app" \
    --app-drop-link 425 190 \
    "$OUTPUT_DMG" \
    "$STAGING_DIR/"

# ---------------------------------------------------------------------------
# Notarization — requires APPLE_ID, APPLE_APP_PASSWORD, and TEAM_ID env vars.
# Only runs when the app was Developer ID signed (not ad-hoc).
# ---------------------------------------------------------------------------
if [[ -n "${SIGNING_IDENTITY:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
    echo "==> Submitting DMG for notarization"
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$OUTPUT_DMG" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1)
    echo "$SUBMIT_OUTPUT"

    # Extract submission ID and fetch log if notarization failed
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep 'id:' | head -1 | awk '{print $2}')
    if echo "$SUBMIT_OUTPUT" | grep -q "status: Invalid"; then
        echo "==> Notarization failed. Fetching log for details:"
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$TEAM_ID" 2>&1 || true
        exit 1
    fi

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$OUTPUT_DMG"
fi

echo "==> Done: $OUTPUT_DMG"
