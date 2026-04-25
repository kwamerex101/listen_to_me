#!/usr/bin/env bash
# Build an ad-hoc signed Release .app and package it as a DMG for personal install.
# No Apple Developer ID, no notarization. First launch: right-click → Open.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [ ! -f ListenToMe/Resources/whisper-cli ]; then
  echo "ERROR: Resources/whisper-cli missing — run ./scripts/setup.sh first" >&2
  exit 1
fi

xcodegen generate >/dev/null

PROJECT="$ROOT/ListenToMe.xcodeproj"
SCHEME="ListenToMe"
DERIVED="$ROOT/build-release"
APP_NAME="ListenToMe.app"
DIST="$ROOT/dist"
DMG_NAME="ListenToMe.dmg"

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

echo "==> Building Release..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE="Automatic" \
  build | tail -20

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Verifying signature..."
codesign -dv "$APP_PATH" 2>&1 | head -5

echo "==> Creating DMG..."
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "ListenToMe" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DIST/$DMG_NAME" >/dev/null

rm -rf "$STAGE"

echo "==> Done."
echo "    App:  $APP_PATH"
echo "    DMG:  $DIST/$DMG_NAME"
echo ""
echo "To install: open '$DIST/$DMG_NAME' and drag ListenToMe to Applications."
echo "First launch: right-click → Open (Gatekeeper warning, since we're not notarized)."
echo "Then grant Microphone permission in System Settings."
