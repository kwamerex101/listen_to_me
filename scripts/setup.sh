#!/bin/bash
# ListenToMe — one-time setup: xcodegen, whisper.cpp, model
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
VENDOR_DIR="$PROJECT_ROOT/vendor/whisper.cpp"
RES_DIR="$PROJECT_ROOT/ListenToMe/Resources"
MODEL_DIR="$HOME/Library/Application Support/ListenToMe/models"
MODEL_FILE="$MODEL_DIR/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

echo "==> 1. Check / install xcodegen"
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew not found. Install from https://brew.sh then rerun." >&2
    exit 1
  fi
  brew install xcodegen
fi
echo "    xcodegen $(xcodegen --version)"

echo "==> 2. Clone whisper.cpp (if needed)"
if [ ! -d "$VENDOR_DIR" ]; then
  mkdir -p "$PROJECT_ROOT/vendor"
  git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$VENDOR_DIR"
fi

echo "==> 3. Build whisper.cpp (with Core ML support)"
pushd "$VENDOR_DIR" >/dev/null
# Newer whisper.cpp uses cmake; try cmake first, fall back to legacy make.
# WHISPER_COREML=1 enables loading <model>-encoder.mlmodelc when present
# (ANE acceleration on Apple Silicon); WHISPER_COREML_ALLOW_FALLBACK=1
# means a missing .mlmodelc package falls back to Metal/CPU silently
# rather than refusing to load the model.
if [ -f CMakeLists.txt ] && command -v cmake >/dev/null 2>&1; then
  cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_COREML=1 \
    -DWHISPER_COREML_ALLOW_FALLBACK=1 \
    >/dev/null
  cmake --build build --config Release -j
  # binary ends up in build/bin/whisper-cli or build/bin/main
  if [ -f build/bin/whisper-cli ]; then
    WHISPER_BIN="$VENDOR_DIR/build/bin/whisper-cli"
  elif [ -f build/bin/main ]; then
    WHISPER_BIN="$VENDOR_DIR/build/bin/main"
  else
    echo "ERROR: whisper.cpp built but no binary at expected path" >&2
    ls -la build/bin || true
    exit 1
  fi
else
  make -j
  WHISPER_BIN="$VENDOR_DIR/main"
fi
popd >/dev/null

echo "==> 4. Copy whisper binaries + dylibs into Resources (portable rpath)"
mkdir -p "$RES_DIR"
# Wipe previously bundled dylibs so stale ones don't linger between runs
rm -f "$RES_DIR"/*.dylib
cp "$WHISPER_BIN" "$RES_DIR/whisper-cli"
chmod +x "$RES_DIR/whisper-cli"

# whisper-server lives next to whisper-cli in the same build/bin dir.
# Optional: only ship it if present; the app degrades gracefully to the
# subprocess CLI path when whisper-server is absent.
WHISPER_SERVER_BIN="$(dirname "$WHISPER_BIN")/whisper-server"
if [ -f "$WHISPER_SERVER_BIN" ]; then
  cp "$WHISPER_SERVER_BIN" "$RES_DIR/whisper-server"
  chmod +x "$RES_DIR/whisper-server"
  echo "    bundled whisper-server (warm-path) alongside whisper-cli"
else
  echo "    note: whisper-server not found; warm path will be unavailable" >&2
fi

# Bundle every dylib whisper-cli depends on (libwhisper + libggml*)
# so the app keeps working regardless of where the project folder lives.
DYLIB_NAMES=$(otool -L "$RES_DIR/whisper-cli" | awk '/^[[:space:]]*@rpath\//{print $1}' | sed 's|@rpath/||')
for lib in $DYLIB_NAMES; do
  # Also pick up transitive deps via fresh search each pass
  SRC=$(find "$VENDOR_DIR/build" -name "$lib" -not -path "*/CMakeFiles/*" | head -1)
  if [ -z "$SRC" ]; then
    echo "    WARN: could not find $lib in $VENDOR_DIR/build" >&2
    continue
  fi
  # Resolve symlinks to copy the real file, then rename to the expected alias
  cp -L "$SRC" "$RES_DIR/$lib"
done

# Walk each bundled dylib's own rpath deps so we pick up transitive ones (e.g. libggml-base)
while :; do
  missing=0
  for bundled in "$RES_DIR"/*.dylib; do
    [ -e "$bundled" ] || continue
    for dep in $(otool -L "$bundled" | awk '/^[[:space:]]*@rpath\//{print $1}' | sed 's|@rpath/||'); do
      if [ ! -f "$RES_DIR/$dep" ]; then
        SRC=$(find "$VENDOR_DIR/build" -name "$dep" -not -path "*/CMakeFiles/*" | head -1)
        if [ -n "$SRC" ]; then
          cp -L "$SRC" "$RES_DIR/$dep"
          missing=1
        fi
      fi
    done
  done
  [ $missing -eq 0 ] && break
done

# Point every binary/dylib at @loader_path (their own directory inside the app
# bundle's Resources folder). Existing absolute rpaths will fail silently and
# @loader_path will resolve correctly.
for f in "$RES_DIR/whisper-cli" "$RES_DIR/whisper-server" "$RES_DIR"/*.dylib; do
  [ -e "$f" ] || continue
  # Drop any build-tree absolute rpaths
  otool -l "$f" | awk '/LC_RPATH/{c=3} c-->0{if (/path /){sub(/.*path /, ""); sub(/ \(offset.*/, ""); print}}' | \
    while read rp; do
      [ -n "$rp" ] && install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
    done
  install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
  # Re-sign ad-hoc so macOS trusts the modified binary
  codesign --force --sign - "$f" 2>/dev/null || true
done
echo "    bundled $(ls "$RES_DIR"/*.dylib 2>/dev/null | wc -l | tr -d ' ') dylibs + whisper-cli"

echo "==> 5. Download Whisper model (if needed)"
mkdir -p "$MODEL_DIR"

# SHA-256 of the canonical Hugging Face ggml-base.en.bin. Keep in
# lockstep with WhisperModelManager.swift expectedSHA256.
EXPECTED_SHA256="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

verify_model_sha() {
  local actual
  actual=$(shasum -a 256 "$MODEL_FILE" | awk '{print $1}')
  if [ "$actual" != "$EXPECTED_SHA256" ]; then
    echo "    ERROR: SHA-256 mismatch for $MODEL_FILE" >&2
    echo "      expected: $EXPECTED_SHA256" >&2
    echo "      actual:   $actual" >&2
    return 1
  fi
}

if [ ! -f "$MODEL_FILE" ]; then
  echo "    downloading ggml-base.en.bin (~148 MB) …"
  curl -L --fail --progress-bar -o "$MODEL_FILE" "$MODEL_URL"
  if ! verify_model_sha; then
    rm -f "$MODEL_FILE"
    exit 1
  fi
  echo "    SHA-256 OK"
else
  echo "    model already present: $MODEL_FILE"
  if ! verify_model_sha; then
    echo "    removing tampered/corrupt copy and re-downloading …" >&2
    rm -f "$MODEL_FILE"
    curl -L --fail --progress-bar -o "$MODEL_FILE" "$MODEL_URL"
    verify_model_sha || { rm -f "$MODEL_FILE"; exit 1; }
    echo "    SHA-256 OK"
  fi
fi

echo "==> 6. Optional Core ML encoder package (Apple Neural Engine accel)"
COREML_DIR="$MODEL_DIR/ggml-base.en-encoder.mlmodelc"
COREML_ZIP_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-encoder.mlmodelc.zip"
if [ -d "$COREML_DIR" ]; then
  echo "    Core ML encoder already present: $COREML_DIR"
else
  TMP_ZIP="$(mktemp -t lm-coreml).zip"
  echo "    downloading ggml-base.en-encoder.mlmodelc (~50 MB) …"
  if curl -L --fail --progress-bar -o "$TMP_ZIP" "$COREML_ZIP_URL"; then
    pushd "$MODEL_DIR" >/dev/null
    if unzip -q "$TMP_ZIP"; then
      echo "    Core ML encoder extracted to $COREML_DIR"
    else
      echo "    WARN: unzip failed; Core ML encoder unavailable (linked engine will use Metal/CPU encoder)" >&2
    fi
    popd >/dev/null
    rm -f "$TMP_ZIP"
  else
    echo "    WARN: Core ML encoder download failed; linked engine will use Metal/CPU encoder" >&2
    rm -f "$TMP_ZIP"
  fi
fi

echo ""
echo "Setup complete. Next: ./scripts/build.sh"
