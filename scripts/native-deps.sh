# ListenToMe — pinned native dependency commits (sourced, not run directly).
#
# Single source of truth for the whisper.cpp and llama.cpp commits the
# shipped binaries are built from. Bump deliberately: both scripts/setup.sh
# and scripts/build-llama.sh read this file, and so does CI's cache key.
# After a bump, re-run both scripts and the test suite before committing.

WHISPER_CPP_REPO="https://github.com/ggml-org/whisper.cpp"
WHISPER_CPP_COMMIT="9386f239401074690479731c1e41683fbbeac557"   # v1.8.4
LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp"
LLAMA_CPP_COMMIT="fdb1db877c526ec90f668eca1b858da5dba85560"     # 2026-07-02, ggml 0.15.3

# Parallel compile jobs for both native builds. A bare `-j` means unlimited
# jobs under the Makefile generator: every translation unit compiles at once,
# which is fine on a big Mac but can push a 3-core / 7 GB CI runner into swap.
# Bounded to the core count; override with BUILD_JOBS=N.
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu)}"

# checkout_pinned <repo-url> <commit> <dir>
#
# Fetches and checks out a pinned commit into <dir>, detached.
#   - Fresh dir (doesn't exist yet): git init, fetch --depth 1 <commit>,
#     checkout FETCH_HEAD.
#   - Existing clone already at <commit>: no-op, returns 0.
#   - Existing clone at a different commit: fetch --depth 1 <commit>,
#     checkout it, and return 10 so the caller knows to wipe its stale
#     build dir.
# GitHub allows fetching a reachable commit directly by SHA, so no full
# clone or tag lookup is needed. Always prints which commit ends up
# checked out.
#
# Callers using `set -euo pipefail` must capture the 10 return code without
# aborting, e.g.: checkout_pinned ... || rc=$?
# Bash disables `set -e` inside a function called from an `||` list, so every
# git step below returns 1 explicitly; otherwise a failed fetch would fall
# through and build the old source.
checkout_pinned() {
  local repo="$1" commit="$2" dir="$3"
  local rc=0

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    git -C "$dir" init -q || return 1
    git -C "$dir" fetch --depth 1 "$repo" "$commit" || return 1
    git -C "$dir" checkout -q FETCH_HEAD || return 1
    echo "    checked out $commit (fresh clone)"
    return 0
  fi

  local current
  current="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")"
  if [ "$current" = "$commit" ]; then
    echo "    already at pinned commit $commit"
    return 0
  fi

  git -C "$dir" fetch --depth 1 "$repo" "$commit" || return 1
  git -C "$dir" checkout -q FETCH_HEAD || return 1
  echo "    checked out $commit (was $current)"
  rc=10
  return "$rc"
}
