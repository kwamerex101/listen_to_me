#!/bin/bash
# ListenToMe — build llama.cpp and bundle libllama + an ISOLATED ggml set.
#
# Why isolated: the app already ships whisper.cpp's ggml 0.9.8 in
# Resources/ (flat). Any llama.cpp new enough for Gemma 4 carries ggml
# >= 0.15, whose ABI differs. The two cannot share one @rpath/libggml.0.dylib.
# Rather than rename symbols, we isolate by DIRECTORY: llama's whole dylib
# set lives in Resources/llm/ with its own @loader_path rpath, so every
# @rpath/libggml*.0.dylib reference resolves to the sibling copy in llm/.
# whisper's set in Resources/ root is untouched. Two ggml copies, zero ABI
# risk, no surgery to the working transcription path.
#
# Run after scripts/setup.sh (which builds + bundles whisper). Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
LLAMA_DIR="$PROJECT_ROOT/vendor/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build-arm64"
LLM_DIR="$PROJECT_ROOT/ListenToMe/Resources/llm"

echo "==> 1. Clone llama.cpp (if needed)"
if [ ! -d "$LLAMA_DIR" ]; then
  mkdir -p "$PROJECT_ROOT/vendor"
  # master carries Gemma 4 (gemma4 arch) + ggml >= 0.15. Metal embedded.
  git clone --filter=blob:none https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

echo "==> 2. Configure (arm64, Metal, embedded metallib, shared libs)"
if [ ! -d "$BUILD_DIR" ]; then
  cmake -B "$BUILD_DIR" -S "$LLAMA_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_CURL=OFF
fi

echo "==> 3. Build the llama library target only"
# The `app/` target needs a generated build-info.h and is irrelevant to us;
# building --target llama produces libllama + its ggml deps and skips it.
cmake --build "$BUILD_DIR" --config Release --target llama -j

BIN="$BUILD_DIR/bin"
INC="$PROJECT_ROOT/ListenToMe/CLlama/include"

echo "==> 3b. Sync public headers into CLlama/include (for the bridge TU)"
# llama_bridge.cpp includes these textually (HEADER_SEARCH_PATHS), never the
# Swift module graph. Generated artifacts (gitignored) — kept in lockstep
# with the built dylib so a llama.cpp bump can't desync header vs binary.
mkdir -p "$INC"
cp "$LLAMA_DIR/include/llama.h" "$INC/"
for h in ggml ggml-cpu ggml-backend ggml-alloc ggml-opt gguf; do
  cp "$LLAMA_DIR/ggml/include/$h.h" "$INC/"
done

echo "==> 4. Bundle into Resources/llm/ with RENAMED ggml (install-name isolation)"
# Directory isolation alone is insufficient: llama's ggml and whisper's ggml
# share the install name @rpath/libggml.0.dylib, and the main executable's
# rpath lists Resources/ (whisper 0.9.8) before Resources/llm/. dyld would
# bind libllama to whisper's OLD ggml -> missing-symbol crash. So we rename
# llama's ggml dylibs to a "-lt" suffix (ListenToMe-llama) and rewrite every
# reference, giving them unique install names that can't collide.
rm -rf "$LLM_DIR"
mkdir -p "$LLM_DIR"

# old @rpath name  ->  new (renamed) name
declare -a GGML=(
  "libggml.0.dylib:libggml-lt.0.dylib"
  "libggml-base.0.dylib:libggml-base-lt.0.dylib"
  "libggml-cpu.0.dylib:libggml-cpu-lt.0.dylib"
  "libggml-metal.0.dylib:libggml-metal-lt.0.dylib"
  "libggml-blas.0.dylib:libggml-blas-lt.0.dylib"
)

# Copy real bytes (resolve symlinks). libllama keeps its name (no whisper
# collision); each ggml lib is copied to its renamed form.
cp -L "$BIN/libllama.dylib" "$LLM_DIR/libllama.0.dylib"
for entry in "${GGML[@]}"; do
  old="${entry%%:*}"; new="${entry##*:}"
  # The build dir's real file is libggml*.0.15.0.dylib via the .dylib symlink.
  cp -L "$BIN/${old%.0.dylib}.dylib" "$LLM_DIR/$new"
done
ln -sf libllama.0.dylib "$LLM_DIR/libllama.dylib"   # link-time alias for -lllama

echo "==> 5. Rewrite install names + cross-references, rpath, re-sign"
for f in "$LLM_DIR"/libllama.0.dylib "$LLM_DIR"/libggml-*-lt.0.dylib "$LLM_DIR"/libggml-lt.0.dylib; do
  [ -e "$f" ] || continue
  # Rewrite every @rpath/<old ggml> reference to the renamed one.
  for entry in "${GGML[@]}"; do
    old="${entry%%:*}"; new="${entry##*:}"
    install_name_tool -change "@rpath/$old" "@rpath/$new" "$f" 2>/dev/null || true
  done
  # Give each renamed ggml lib its new install id.
  base="$(basename "$f")"
  case "$base" in
    libggml*-lt.0.dylib) install_name_tool -id "@rpath/$base" "$f" 2>/dev/null || true ;;
  esac
  # Drop build-tree absolute rpaths; resolve siblings from own dir.
  otool -l "$f" | awk '/LC_RPATH/{c=3} c-->0{if (/path /){sub(/.*path /,"");sub(/ \(offset.*/,"");print}}' | \
    while read -r rp; do
      [ -n "$rp" ] && install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
    done
  install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
  codesign --force --sign - "$f" 2>/dev/null || true
done

echo "    bundled $(ls "$LLM_DIR"/*.dylib 2>/dev/null | wc -l | tr -d ' ') files in Resources/llm/"
echo "Done. libllama uses renamed (-lt) ggml; whisper's ggml untouched."
