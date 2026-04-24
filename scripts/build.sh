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
echo ""
echo "Built: $APP"
echo "Launch with: open \"$APP\""
