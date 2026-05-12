#!/usr/bin/env bash
set -euo pipefail

# Builds, archives, and (optionally) notarizes the VoiceMiddle.app bundle
# into a signed DMG dropped at dist/VoiceMiddle-<version>.dmg.
#
# Usage:
#   scripts/release.sh                  # dry run: build + dmg, no notarize
#   scripts/release.sh --notarize       # full release flow
#
# Required env vars for --notarize mode:
#   APPLE_ID                Apple Developer email
#   APPLE_TEAM_ID           10-char team identifier
#   APPLE_APP_SPECIFIC_PASSWORD   app-specific password for notarytool
#
# The script depends on `create-dmg` (https://github.com/create-dmg/create-dmg)
# being on PATH; install via `brew install create-dmg`.

cd "$(dirname "$0")/.."

NOTARIZE=0
if [[ "${1:-}" == "--notarize" ]]; then
    NOTARIZE=1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    VoiceMiddle/VoiceMiddle/Info.plist || echo "0.0.0")"

mkdir -p dist build
ARCHIVE_PATH="build/VoiceMiddle.xcarchive"
EXPORT_PATH="build/Export"
DMG_PATH="dist/VoiceMiddle-${VERSION}.dmg"

EXPORT_OPTIONS="build/exportOptions.plist"
cat > "$EXPORT_OPTIONS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

echo "==> Archive"
xcodebuild archive \
    -workspace VoiceMiddle.xcworkspace \
    -scheme VoiceMiddle \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    | xcbeautify || true

echo "==> Export"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    | xcbeautify || true

APP_PATH="$EXPORT_PATH/VoiceMiddle.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: $APP_PATH not produced by exportArchive"
    exit 1
fi

if (( NOTARIZE )); then
    : "${APPLE_ID:?APPLE_ID must be set for --notarize}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID must be set}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD must be set}"

    ZIP_PATH="build/VoiceMiddle.zip"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "==> notarytool submit"
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait

    echo "==> staple"
    xcrun stapler staple "$APP_PATH"
fi

echo "==> create-dmg"
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg not found on PATH; skip DMG step."
    echo "Install with: brew install create-dmg"
    exit 0
fi
rm -f "$DMG_PATH"
create-dmg \
    --volname "VoiceMiddle $VERSION" \
    --window-size 540 360 \
    --icon-size 96 \
    --app-drop-link 380 200 \
    --icon "VoiceMiddle.app" 160 200 \
    "$DMG_PATH" \
    "$APP_PATH"

echo "==> spctl assess"
spctl --assess --type install --verbose "$DMG_PATH" || true

echo "All done: $DMG_PATH"
