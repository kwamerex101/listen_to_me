# Wave 6 ADR — On-device Gemma polish runtime

Date: 2026-06-11
Status: **Decided on runtime; blocked on ggml-integration fork (needs sign-off).**

## Decision 1: Runtime = llama.cpp (GGUF), not MLX-Swift

Two independent Opus spikes reached the same verdict.

- The app already ships the **ggml stack** (`libggml-base/cpu/metal/blas/ggml.0.dylib`) + `libwhisper.1.dylib`, bridged via the `CWhisper` Clang module map, bundled by the `setup.sh` rpath/codesign loop, with `com.apple.security.cs.disable-library-validation` already carved out. llama.cpp **is the same ggml ecosystem** → add one `libllama.dylib`, reuse Metal/signing/bundling.
- MLX would add a **second inference runtime + second Metal allocator**, 4 SPM packages (repo has zero today), ~100–200 MB, and a Swift-tools 6.1 bump. Not justified.
- Gemma 4 E2B is supported by llama.cpp (`general.architecture = gemma4`). Default weight: `gemma-4-E2B-it-Q4_K_M.gguf` (3.11 GB, `unsloth/` or `ggml-org/` GGUF). 12B Q4_K_M (7.38 GB) behind an explicit quality toggle.

## Decision 2 (BLOCKED): how to get a version-matched libllama

The spike flagged ggml ABI matching as the one must-verify-empirically risk. Verified — and it's a real conflict:

| llama.cpp date | vendored ggml | has `gemma4`? |
|---|---|---|
| 2026-03-25 | **0.9.8** (== our whisper) | No (Gemma 4 launched 2026-04-02) |
| 2026-04-20 | 0.9.11 | — |
| master | 0.15.0 | Yes |

Our `vendor/whisper.cpp` (commit fc67457, 2026-04-20) pins **ggml 0.9.8**. Any llama.cpp new enough for `gemma4` carries ggml ≥0.9.11. **So we cannot drop `libllama` next to the existing ggml 0.9.8 dylibs** — the install names collide (`@rpath/libggml.0.dylib`) but the ABIs differ.

### Path A — Unify ggml (one copy, both runtimes)
Re-vendor whisper.cpp to a recent commit whose ggml matches a `gemma4`-capable llama.cpp; rebuild both from one ggml; bundle a single ggml set.
- Pro: one ggml, smaller bundle, "correct".
- Con: **re-vendoring whisper risks regressing the shipping transcription path** — `WhisperLib.swift` calls a specific whisper API surface; a newer whisper.cpp may have changed it. Requires full re-verification of the linked/CLI/server engines.

### Path B — Isolate ggml (two copies, renamed install names) — **RECOMMENDED**
Keep whisper's ggml 0.9.8 untouched. Build llama.cpp at master (gemma4 + ggml 0.15). Rename llama's ggml dylibs to a distinct prefix (e.g. `libggml-llama-*.dylib`) and `install_name_tool -change` every edge in the llama→ggml dependency graph so the two runtimes never share a dylib. Bundle both sets.
- Pro: **zero risk to the working whisper pipeline**; no whisper re-vendor.
- Con: ~3–4 MB extra (second ggml), install-name surgery in the build script, two Metal backends initialized in-process (separate symbol namespaces → fine, just more memory).

## Verified llama.cpp C API (current, non-deprecated) — for implementation
`llama_backend_init` → `llama_model_load_from_file` (NOT `llama_load_model_from_file`) → `llama_model_get_vocab` → `llama_init_from_model` (NOT `llama_new_context_with_model`) → `llama_chat_apply_template(NULL, msgs, …)` (Gemma template embedded in GGUF) → `llama_tokenize(vocab, …)` → sampler chain `llama_sampler_chain_init` + `llama_sampler_init_greedy` → loop `llama_batch_get_one` + `llama_decode` + `llama_sampler_sample` + `llama_vocab_is_eog` + `llama_token_to_piece` → free `llama_sampler_free`/`llama_free`/`llama_model_free` (NOT `llama_free_model`)/`llama_backend_free`.

Build flags: `-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=ON -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF`. `GGML_METAL_EMBED_LIBRARY=ON` is mandatory for us — avoids the `default.metallib`-not-found bug for shared libs in a relocated bundle.

## Implementation outline (post-decision)
1. `setup.sh`: clone+build llama.cpp (chosen path), bundle `libllama.dylib` (+ isolated ggml if Path B), rpath/codesign like whisper.
2. `CLlama/include/` module map + `llama.h` (+ ggml headers).
3. `project.yml`: add CLlama include paths (app + test target), `-lllama` in `OTHER_LDFLAGS`, exclude `CLlama/**` from sources.
4. `LLMModelManager.swift` — mirror `WhisperModelManager` (download GGUF to Application Support, SHA256 verify, progress, disk-space guard, Gemma license surfaced in-app).
5. `LocalLLMEngine.swift` — mirror `WhisperLib` lifecycle (lazy load off-main, MainActor adoption, in-flight gate, `preload()`/`shutdown()`, per-call context).
6. `Preferences`: `LLMBackend` enum `claude | local`; route in `ClaudeClient.clean()`. Settings "On-Device Model" picker (E2B default; 12B gated on ≥16 GB RAM).
7. Reuse layered prompt (context → tone → vocabulary → base rules) via Gemma chat template.
8. Tests: punctuation-preserves-words property test, latency baseline (E2B < ~1.5s/100 words), model-swap stress, leak (free ctx in deinit), memory-pressure handler.
