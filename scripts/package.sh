#!/usr/bin/env bash
set -euo pipefail

# Packages a notarizable Release build of SidePrompt.
# Usage:
#   ./scripts/package.sh
# Optional env:
#   DEVELOPMENT_TEAM=NG3LT5T97Q
#   NOTARIZE=1 APPLE_ID=... APP_PASSWORD=... TEAM_ID=...

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
APP_NAME="SidePrompt"
SCHEME="SidePrompt"
TEAM="${DEVELOPMENT_TEAM:-NG3LT5T97Q}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :settings:base:MARKETING_VERSION' "$ROOT/project.yml" 2>/dev/null || true)"
# Fallback: read from built Info later

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "→ Building Release…"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination "platform=macOS" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build

APP_SRC="$(find "$BUILD_DIR/DerivedData/Build/Products/Release" -name "$APP_NAME.app" -maxdepth 2 | head -n1)"
if [[ -z "$APP_SRC" ]]; then
  echo "App not found in Release products" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_SRC/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_SRC/Contents/Info.plist")"
STAGE="$BUILD_DIR/$APP_NAME-$VERSION"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_SRC" "$STAGE/$APP_NAME.app"

echo "→ Creating ZIP for Sparkle…"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/$APP_NAME.app" "$ZIP"

echo "→ Creating DMG…"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "✓ Packaged"
echo "  App: $STAGE/$APP_NAME.app"
echo "  ZIP: $ZIP"
echo "  DMG: $DMG"
echo "  Version: $VERSION ($BUILD)"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APP_PASSWORD:-}" || -z "${TEAM_ID:-}" ]]; then
    echo "NOTARIZE=1 requires APPLE_ID, APP_PASSWORD (app-specific), TEAM_ID" >&2
    exit 1
  fi
  echo "→ Submitting for notarization…"
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
  xcrun stapler staple "$DMG"
  echo "✓ Notarized and stapled: $DMG"
else
  echo
  echo "Notarize later with:"
  echo "  NOTARIZE=1 APPLE_ID=you@example.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx TEAM_ID=$TEAM ./scripts/package.sh"
fi

echo
echo "Sparkle next steps:"
echo "  1) brew install sparkle  # or use bin from Sparkle release"
echo "  2) generate_keys  → put public key in Info.plist SUPublicEDKey"
echo "  3) sign_update \"$ZIP\"  → paste into docs/appcast.xml"
echo "  4) Host ZIP + appcast at SUFeedURL"
