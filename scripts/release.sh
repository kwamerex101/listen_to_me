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
SIGN_NAME="$SIGN_IDENTITY"
if [ -z "$SIGN_IDENTITY" ]; then
  IDS="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  DEVID_LINE="$(printf '%s\n' "$IDS" | grep '"Developer ID Application:' | head -1 || true)"
  if [ -n "$DEVID_LINE" ]; then
    # Sign by SHA-1, not by name: codesign rejects a name as "ambiguous"
    # when the keychain holds two certificates with the same name (e.g. a
    # Developer ID certificate that was issued twice).
    SIGN_IDENTITY="$(printf '%s\n' "$DEVID_LINE" | awk '{print $2}')"
    SIGN_NAME="$(printf '%s\n' "$DEVID_LINE" | grep -oE '"[^"]*"' | tr -d '"')"
  fi
fi
DEV_ID=0
case "$SIGN_NAME" in
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

  # Sparkle 2's own documented signing order: inside-out through the
  # framework's nested XPC services / helper executables, THEN the
  # framework itself. Must happen before the outer app is signed below.
  # The generic dylib loop above only globs "*.dylib" / "*.debug.dylib",
  # so it never touches any of these (none of them match that pattern),
  # nothing here gets re-signed afterwards with the wrong flags.
  SPARKLE_FMW="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
  if [ -d "$SPARKLE_FMW" ]; then
    echo "==> Signing Sparkle.framework nested code..."
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$SPARKLE_FMW/XPCServices/Installer.xpc" >/dev/null
    # Downloader.xpc is sandboxed and ships with its own entitlements
    # (app-sandbox, network.client); --preserve-metadata=entitlements keeps
    # those intact instead of stripping them on re-sign.
    codesign --force --options runtime --timestamp \
      --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" \
      "$SPARKLE_FMW/XPCServices/Downloader.xpc" >/dev/null
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$SPARKLE_FMW/Autoupdate" >/dev/null
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$SPARKLE_FMW/Updater.app" >/dev/null
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$APP_PATH/Contents/Frameworks/Sparkle.framework" >/dev/null
  fi

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

# ---- Appcast -------------------------------------------------------------
# An update must never ship un-notarized, so skip appcast generation
# entirely (loudly) rather than produce a feed entry Gatekeeper would
# reject on the installing machine.
APPCAST_GENERATED=0
if [[ "$NOTARIZED" != "1" ]]; then
  echo ""
  echo "⚠️  WARNING: skipping appcast generation: the DMG is not notarized."
  echo "    An auto-update feed must only ever point at a notarized build."
else
  echo "==> Generating appcast..."

  GENERATE_APPCAST="$(find "$DERIVED/SourcePackages" -path "*Sparkle*/bin/generate_appcast" -maxdepth 8 -type f 2>/dev/null | head -1)"
  if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "⚠️  WARNING: generate_appcast not found under $DERIVED/SourcePackages: skipping appcast." >&2
  else
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"

    ARCHIVE_DIR="$DIST/appcast-stage"
    rm -rf "$ARCHIVE_DIR"
    mkdir -p "$ARCHIVE_DIR"
    cp "$DIST/$DMG_NAME" "$ARCHIVE_DIR/"

    # Release notes: pull this version's section out of CHANGELOG.md into a
    # Markdown file generate_appcast will pick up by matching basename
    # (generate_appcast 2.10.0 supports .html, .md, and .txt release notes).
    NOTES_FILE="$ARCHIVE_DIR/${DMG_NAME%.dmg}.md"
    awk -v ver="$VERSION" '
      BEGIN { found = 0 }
      /^## / {
        if (found) exit
        if (index($0, ver) > 0) { found = 1; next }
        next
      }
      found { print }
    ' "$ROOT/CHANGELOG.md" > "$NOTES_FILE"
    if [[ ! -s "$NOTES_FILE" ]]; then
      echo "⚠️  WARNING: no CHANGELOG.md section found for $VERSION: appcast item will have no release notes." >&2
      rm -f "$NOTES_FILE"
    fi

    "$GENERATE_APPCAST" \
      --download-url-prefix "https://github.com/kwamerex101/listen_to_me/releases/download/v$VERSION/" \
      --embed-release-notes \
      -o "$DIST/appcast.xml" \
      "$ARCHIVE_DIR"

    rm -rf "$ARCHIVE_DIR"

    if [[ -f "$DIST/appcast.xml" ]]; then
      APPCAST_GENERATED=1
      echo "==> Appcast: $DIST/appcast.xml"
    else
      echo "⚠️  WARNING: generate_appcast ran but $DIST/appcast.xml was not produced." >&2
    fi
  fi
fi

echo ""
echo "==> Done."
echo "    App:  $APP_PATH"
echo "    DMG:  $DIST/$DMG_NAME"
if [[ "$APPCAST_GENERATED" == "1" ]]; then
  echo "    Appcast: $DIST/appcast.xml"
  echo "    Upload BOTH dist/$DMG_NAME and dist/appcast.xml to the GitHub Release v$VERSION."
fi
if [[ "$NOTARIZED" == "1" ]]; then
  echo "    Signed (Developer ID) + notarized + stapled — double-click to install."
elif [[ "$DEV_ID" == "1" ]]; then
  echo "    Signed (Developer ID), NOT notarized — Gatekeeper may still warn on download."
else
  echo "    Ad-hoc signed — first launch: right-click → Open (Gatekeeper warning)."
fi
echo "    Then grant Microphone + Accessibility in System Settings."
