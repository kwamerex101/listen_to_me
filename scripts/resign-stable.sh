#!/bin/bash
# Re-sign a built ListenToMe.app with a STABLE code-signing identity so macOS
# TCC can persist permission decisions across launches.
#
# Why this exists: the Xcode build signs ad-hoc (CODE_SIGN_IDENTITY "-").
# TCC keys every permission grant/denial to the app's signing identity, and an
# ad-hoc signature has no stable identity — so macOS re-prompts for mic / media
# / Apple Events on essentially every launch or protected access. Signing with
# a real "Apple Development" (or "Developer ID Application") cert gives a stable
# TeamIdentifier, and the prompts stick after the first answer.
#
# Degrades gracefully: if no suitable identity is in the keychain, it leaves the
# ad-hoc signature untouched and exits 0, so CI / other machines still work.
#
# Usage: scripts/resign-stable.sh /path/to/ListenToMe.app
set -euo pipefail

APP="${1:?usage: resign-stable.sh <path-to-.app>}"
[ -d "$APP" ] || { echo "resign-stable: not a bundle: $APP" >&2; exit 1; }

# Prefer Developer ID (distributable) over Apple Development (local dev).
# `|| true` so a no-match grep under `set -o pipefail` doesn't abort the script.
IDS="$(security find-identity -v -p codesigning 2>/dev/null || true)"
ID="$(printf '%s\n' "$IDS" | grep -oE '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)"
if [ -z "$ID" ]; then
  ID="$(printf '%s\n' "$IDS" | grep -oE '"Apple Development:[^"]*"' | head -1 | tr -d '"' || true)"
fi

if [ -z "$ID" ]; then
  echo "resign-stable: no Developer ID / Apple Development identity found — leaving ad-hoc signature (TCC will re-prompt)."
  exit 0
fi

echo "resign-stable: signing with [$ID]"

# codesign's --entitlements parser (AMFI) rejects XML comments that Xcode's
# signer tolerates, so feed it a comment-free copy of the same entitlements.
ENT_SRC="$(cd "$(dirname "$0")/.." && pwd)/ListenToMe/ListenToMe.entitlements"
ENT_TMP="$(mktemp -t ltm-entitlements).plist"
trap 'rm -f "$ENT_TMP"' EXIT
# Strip comments by round-tripping through plutil (drops <!-- ... -->).
plutil -convert xml1 -o "$ENT_TMP" "$ENT_SRC"

# Sign inside-out: nested dylibs and helper executables first, then the bundle.
while IFS= read -r -d '' f; do
  codesign --force --options runtime --timestamp=none --sign "$ID" "$f" >/dev/null
done < <(find "$APP/Contents" \( -name "*.dylib" -o -name "*.debug.dylib" \) -print0)

for bin in whisper-cli whisper-server; do
  [ -f "$APP/Contents/Resources/$bin" ] && \
    codesign --force --options runtime --timestamp=none --sign "$ID" "$APP/Contents/Resources/$bin" >/dev/null
done

codesign --force --options runtime --timestamp=none \
  --entitlements "$ENT_TMP" --sign "$ID" "$APP" >/dev/null

codesign --verify --deep --strict "$APP"
TEAM="$(codesign -dvvv "$APP" 2>&1 | grep -i 'TeamIdentifier' || true)"
echo "resign-stable: done — $TEAM"
