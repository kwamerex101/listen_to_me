#!/bin/bash
# ListenToMe — generate xcodeproj and build Debug
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f ListenToMe/Resources/whisper-cli ]; then
  echo "ERROR: Resources/whisper-cli missing — run ./scripts/setup.sh first" >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild (Debug)"
xcodebuild \
  -project ListenToMe.xcodeproj \
  -scheme ListenToMe \
  -configuration Debug \
  -derivedDataPath build \
  build | tail -n 30

APP="$(pwd)/build/Build/Products/Debug/ListenToMe.app"

# Re-sign with a stable identity so macOS TCC persists permission decisions
# (the Xcode build signs ad-hoc, which makes the OS re-prompt every launch).
# No-op if no Developer ID / Apple Development identity is in the keychain.
"$(dirname "$0")/resign-stable.sh" "$APP" || true

echo ""
echo "Built: $APP"
echo "Launch with: open \"$APP\""
