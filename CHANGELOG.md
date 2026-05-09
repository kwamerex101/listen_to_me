# Changelog

All notable user-facing changes per release. Format inspired by [Keep a Changelog](https://keepachangelog.com/), version numbers follow [SemVer](https://semver.org/) at the bundle level.

## [Unreleased]

These changes are merged to `main` but not yet tagged or installed in `/Applications`. Bump the version in `project.yml`, tag, and run `scripts/release.sh` to ship.

### Added — Wispr UX parity (M3)

- **Backtrack voice command** — start a dictation with "actually, …", "scratch that, …", "wait, change that to …", or "i meant …" to revise the previous paste in place via Claude rather than appending a new one. Three-gate `Paster.replace` validation prevents clobbering if focus moved.
- **App + URL context awareness** — cleanup prompt now includes the target app's bundleId, display name, coarse category (codeEditor / browser / messaging / email / document / terminal / other), and — for known browsers (Safari, Chrome, Brave, Arc, Edge, Vivaldi) — the front-tab URL. Bounded AppleScript probe with 0.3 s hard timeout.
- **Code-mode cleanup** — when the target is a code editor or terminal (Cursor, Xcode, VS Code, iTerm, Warp, Zed, Hyper, IntelliJ family, Sublime), cleanup uses a casing-aware variant that recognizes "camel/pascal/snake/kebab/screaming snake case <words>", holds keywords lowercase (for, while, if, return, function, class, const, let, var, def, async, await, true/false/null/none …), and resolves homophones in code context.
- **Auto-personal-dictionary mining** — at launch, scan `HistoryStore` for single-word swaps the cleanup pass consistently fixed (e.g. "danqua" → "Danquah"). Conservative filters exclude capitalization-only diffs and multi-word rewrites. Three distinct occurrences auto-promote to the dictionary, biasing future whisper transcriptions toward the correct rendering.
- **Drag-to-reposition pill** — grab and drop the floating pill anywhere on screen; position persists per launch and survives display reconfigurations. Settings → Advanced → "Pill position" → Reset returns to default.
- **Auto-shrink to a 10 pt dot** after 5 s of true idle. Hover or any phase transition wakes instantly.
- **Cancel button during transcribing / cleaning / polishing** — abort in-flight pipelines without force-quit. `Task.isCancelled` short-circuits the result if it eventually arrives.
- **VoiceOver labels per phase** + reduce-motion gating on the idle breath, recording-dot heartbeat, and 30 Hz waveform animations.
- **Polish / Transform menu** on history rows — re-run any of the seven built-in transforms (Make formal / Make casual / Tighten / Bulletize / Summarize / Translate to Spanish / Translate to French) or any user-defined `TransformsStore` entry against an existing transcript. Result writes to the pasteboard.

### Added — Foundations (PR #18)

- **Direct Anthropic API path** alongside the `claude` CLI subprocess. Set an Anthropic API key in Settings → AI Cleanup; `Auto` backend prefers the direct path with `cache_control: ephemeral` prompt caching. Target latency: ~250–500 ms vs the CLI's ~1.5–3 s.
- **Persistent whisper-server warm path** — the bundled `whisper-server` binary runs as a launched-on-demand subprocess so the 148 MB model stays resident across dictations. First dictation pays the model-load cost (~1–8 s on cold cache, capped 20 s); every subsequent one is HTTP-only. Falls back to `whisper-cli` subprocess on any error.
- **NDJSON history** — `history.ndjson` (line-delimited) replaces the legacy pretty-printed JSON array. `add()` is now O(1) single-line append off-main; only `remove`/`updateLast`/retention do a debounced full rewrite. Auto-migrates from `history.json` once on first launch (kept at `history.json.bak`).
- **Optional at-rest encryption for `history.ndjson`** — Settings → Advanced → "Encrypt history at rest" toggle. AES-GCM per line with a 256-bit key in the macOS Keychain. Per-line scheme preserves the constant-time append property. Off by default to avoid forcing existing users through a one-time migration.
- **Cleanup-backend picker** — Settings → AI Cleanup → Backend: Auto / CLI / API.
- **History retention** — Settings → Advanced → "History retention" slider (0–365 days, default 90; 0 = forever). Apply button immediately purges older records.
- **Diagnostics log toggle** — `retype-debug.log` is off by default and rotates at 1 MB when enabled.

### Changed

- **Hardened runtime ON for Release** (was a silent no-op under adhoc signing before). Verified `flags=0x10002(adhoc,runtime)`. Debug intentionally skips the runtime flag because library validation rejects Xcode's per-build SwiftUI-previews dylib under adhoc signing.
- **Stripped `com.apple.security.get-task-allow` from Release builds** via `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`. Release now ships only the entitlements declared in `ListenToMe.entitlements` (audio-input + apple-events).
- **Phase-change polling loop replaced** with a Combine sink on `AppState.$phase`. Eliminates ~6.7 wake-ups/sec at idle.
- **`AudioRecorder.process()`** is now `nonisolated` with `NSLock`-guarded shared state. Was crossing into `@MainActor` from the audio render thread — latent race during teardown.
- **`WhisperRunner` drains stderr/stdout via `readabilityHandler`** instead of `readDataToEndOfFile()` in the termination handler. Prevents pipe deadlock on >64 KB stderr.
- **`AudioRecorder.onLevel` callback gated to `.recording` phase** so stale tail callbacks don't churn `@Published` subscribers.
- **`Paster.paste()` and `Paster.replace()` prior-pasteboard restore is `changeCount`-gated** so a copy made during the 600 ms restore window isn't clobbered.
- **Whisper `--prompt` length capped at 1024 chars** as defense-in-depth.

### Security

- **SHA-256 verification of `ggml-base.en.bin`** on every launch via `WhisperModelManager.refreshStatus()`. Mismatch removes the file and surfaces a re-download error. Streamed in 1 MB chunks via CryptoKit. Mirrored in `setup.sh`.
- **Keychain helper** (`Core/Keychain.swift`) — generic-password wrapper used for the Anthropic API key and the history encryption key. Service `com.rexdanquah.listentome`, accessibility `WhenUnlocked`.
- **AppleEvents entitlement** added (`com.apple.security.automation.apple-events`). `Info.plist` advertised the usage string for ages but the entitlement was missing.
- **`SECURITY.md` rewritten** to match the actual code path (the prior version referenced a `claude_local_api` localhost proxy that no longer exists).

### Tests

- **102 tests, 0 failures** across 11 suites (was 24 across 4):
  - `BacktrackTests` (16) — leading-trigger detection + false-positive guards
  - `HistoryDictionaryMinerTests` (12) — single-word swap detection + exclusions
  - `AppContextTests` (11) — promptLine assembly + allowlist sanity
  - `ClaudeClientSanitizeTests` (12) — quote/fence stripping, preamble rejection, word-count guard
  - `HistoryStoreNDJSONTests` (6) — round-trip + partial recovery + legacy decoder
  - `HistoryCipherTests` (10) — AES-GCM round-trip, fresh-nonce safety, tampered-ciphertext rejection, base64 shape, detection heuristic
  - `HistoryStoreEncryptedNDJSONTests` (3) — encrypted round-trip, mixed encrypted+plaintext lines, missing-key skip
  - `BuiltinTransformsTests` (6) — catalog structure, unique ids, label sizing, instruction quality
  - `RetypeDifferTests` (9), `SnippetsStoreTests` (2), `ToneInferencerTests` (6), `VoiceEditorTests` (8) — unchanged

### Removed

- **`CLAUDE.md` is no longer tracked.** Per-developer Claude Code project memory belongs in the working tree, not version control. Mirrored in `.gitignore` for `CLAUDE.local.md`, `GEMINI.md`, `AGENTS.md`.

### Internal

- **Cached PATH augmentation** in `ClaudeClient` instead of recomputing per call.
- **`HistoryStore.parseNDJSON` and `writeAll` made `internal`** (still `nonisolated`) so the test suite can verify round-trip without the singleton.
- **Reused `ISO8601DateFormatter`** in `retype-debug.log` writer (was allocated per call).
- `WhisperServer` startup-readiness cap raised from 8 s to 20 s after smoke caught a model-load race on cold cache.

## [v0.12.0] — 2026-05-06

Pre-foundation milestone. See [PR #17 (Omnibus)](https://github.com/kwamerex101/listen_to_me/pull/17).

- Per-app activity card in Home
- QUAL / CORR / CORR-02 follow-ons
- Design polish refinements

## [v0.11.0] — 2026-05-06

UX/UI polish + micro-animations: hover/press feedback, cross-fade tab transitions, silence-dim waveform after 5 s quiet, tuned pill morph spring, gold flash on dictionary auto-promotion. See [PR #16](https://github.com/kwamerex101/listen_to_me/pull/16).

## [v0.10.0] — 2026-05-06

Per-app style tuning. After 20 dictations into the same app, ListenToMe infers a tone (`casual` / `formal` / `code` / `markdown`) and offers it once via a Keep / Dismiss banner. See [PR #15](https://github.com/kwamerex101/listen_to_me/pull/15).

## Earlier

See `git log --oneline` and the merged-PR history on GitHub for v0.7 through v0.9. Highlights were multi-display anchoring (v0.7), selection-aware paste (v0.8), and the auto-learning dictionary (v0.9).
