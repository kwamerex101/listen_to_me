#!/usr/bin/env bash
# Build a Release .app and package it as a DMG.
#
# Signing is auto-detected from the keychain:
#   * Developer ID Application identity present  -> deep-sign with hardened
#     runtime + secure timestamp, sign the DMG, and (if a notarytool profile
#     exists) notarize + staple. This is the friction-free "download & open"
#     path for public distribution.
#   * Otherwise -> stable/ad-hoc resign via resign-stable.sh. The DMG works
#     but Gatekeeper requires a one-time right-click -> Open.
#
# Overrides (env):
#   SIGN_IDENTITY   Force a specific signing identity string.
#   NOTARY_PROFILE  notarytool keychain profile name (default: ListenToMe).
#                   Create once with:
#                     xcrun notarytool store-credentials ListenToMe \
#                       --apple-id <you> --team-id <TEAMID> \
#                       --password <app-specific-password>
#   SKIP_NOTARIZE=1 Developer-ID sign but skip notarization.
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
NOTARY_PROFILE="${NOTARY_PROFILE:-ListenToMe}"

# ---- Resolve signing identity -------------------------------------------------
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  IDS="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  SIGN_IDENTITY="$(printf '%s\n' "$IDS" | grep -oE '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)"
fi
DEV_ID=0
case "$SIGN_IDENTITY" in
  "Developer ID Application:"*) DEV_ID=1 ;;
esac

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

# ---- Sign --------------------------------------------------------------------
if [[ "$DEV_ID" == "1" ]]; then
  echo "==> Deep-signing for notarization with [$SIGN_IDENTITY]"
  # AMFI rejects XML comments in the entitlements; feed a comment-free copy.
  ENT_TMP="$(mktemp -t ltm-entitlements).plist"
  trap 'rm -f "$ENT_TMP"' EXIT
  plutil -convert xml1 -o "$ENT_TMP" "$ROOT/ListenToMe/ListenToMe.entitlements"

  # Inside-out: nested dylibs + helper executables first, then the bundle.
  # --timestamp (secure, online) is REQUIRED for notarization — unlike
  # resign-stable.sh which uses --timestamp=none for local TCC stability.
  while IFS= read -r -d '' f; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$f" >/dev/null
  done < <(find "$APP_PATH/Contents" \( -name "*.dylib" -o -name "*.debug.dylib" \) -print0)

  for bin in whisper-cli whisper-server; do
    [ -f "$APP_PATH/Contents/Resources/$bin" ] && \
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        "$APP_PATH/Contents/Resources/$bin" >/dev/null
  done

  codesign --force --options runtime --timestamp \
    --entitlements "$ENT_TMP" --sign "$SIGN_IDENTITY" "$APP_PATH" >/dev/null
  codesign --verify --deep --strict "$APP_PATH"
else
  echo "==> No Developer ID identity found — using stable/ad-hoc resign (NOT notarizable)."
  "$(dirname "$0")/resign-stable.sh" "$APP_PATH" || true
fi

echo "==> Verifying signature..."
# `| head` would SIGPIPE codesign under `set -o pipefail` and abort the run;
# sed consumes the whole stream, and `|| true` keeps this purely informational.
codesign -dv "$APP_PATH" 2>&1 | sed -n '1,5p' || true

# ---- Package DMG -------------------------------------------------------------
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

# ---- Notarize ----------------------------------------------------------------
NOTARIZED=0
if [[ "$DEV_ID" == "1" ]]; then
  # Sign the DMG itself so the staple has something to attach to.
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$DMG_NAME"
  if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "==> SKIP_NOTARIZE=1 — Developer-ID signed but not notarized."
  elif xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarizing (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DIST/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DIST/$DMG_NAME"
    xcrun stapler staple "$APP_PATH" || true
    NOTARIZED=1
    echo "==> Notarized + stapled."
  else
    echo "==> No notarytool profile '$NOTARY_PROFILE' found — DMG is Developer-ID signed but NOT notarized."
    echo "    Create one: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "                  --apple-id <you> --team-id <TEAMID> --password <app-specific-password>"
  fi
fi

echo ""
echo "==> Done."
echo "    App:  $APP_PATH"
echo "    DMG:  $DIST/$DMG_NAME"
if [[ "$NOTARIZED" == "1" ]]; then
  echo "    Signed (Developer ID) + notarized + stapled — double-click to install."
elif [[ "$DEV_ID" == "1" ]]; then
  echo "    Signed (Developer ID), NOT notarized — Gatekeeper may still warn on download."
else
  echo "    Ad-hoc signed — first launch: right-click → Open (Gatekeeper warning)."
fi
echo "    Then grant Microphone + Accessibility in System Settings."
