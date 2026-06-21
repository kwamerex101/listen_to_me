# Changelog

All notable user-facing changes per release. Format inspired by [Keep a Changelog](https://keepachangelog.com/), version numbers follow [SemVer](https://semver.org/) at the bundle level.

## 0.17.0 (build 39)

### Added

- **Clear all history** — a one-click button on the History page (with confirm) wipes your entire dictation history.

### Changed

- **Redesigned the first-run onboarding** — a cleaner five-step flow (welcome → voice-engine download → permissions → hotkey and microphone → a live practice screen where you actually try a dictation before finishing), matching the rest of the app's look. Output-destination setup moved into Settings to keep first-run simple. All motion respects Reduce Motion; permissions update live as you grant them.

## 0.16.0 (build 38)

### Added

- **Uninstall** — Settings → Privacy → "Uninstall & delete all data". A confirm dialog deletes all downloaded models, dictation history, your custom dictionary, settings, and the API + history-encryption keys from the Keychain, then moves the app to the Trash. Optional toggle to also delete your daily notes (`~/Documents/daily`). macOS permission grants (Microphone / Accessibility / Automation) must be removed manually in System Settings — the app opens the Privacy pane for you.

## 0.15.0 (build 37)

### Added
- **Output destinations.** Settings → Dictation → Output now lets you choose where a finished dictation lands: the active app (paste, default), the clipboard (copy only), or **Apple Notes**. For Apple Notes, pick a mode — append to one note, a new note each time, or a daily note — and configure the note name and folder.
- **First-run onboarding.** A five-screen walkthrough (practice, speech-model download, permissions, hotkey & microphone, output) shown once on first launch. The speech-model screen downloads Whisper Base in the background so the app is ready to transcribe.

### Changed
- **Encryption key is now created lazily.** The history-at-rest encryption key is only generated/accessed when you turn on "Encrypt history at rest" in Settings → Privacy — not on every launch. Fresh installs no longer trigger a Keychain prompt unless you opt into encryption.

### Notes
- Choosing the Apple Notes destination triggers a one-time macOS prompt to allow ListenToMe to control Notes. Text is written locally via Apple Events — nothing leaves your Mac.

## [Unreleased]

### Added — SQLite storage foundation (M6, partial)

- **`Core/Storage/Database.swift`** — thin Swift wrapper around the system SQLite3 C API. Single connection per process, opened lazily on first `connect()` and reused for the session. WAL journal mode + `synchronous=NORMAL` for durable atomic writes per row at the right cost for our write rate. `SQLValue` sum type (`null`/`integer`/`real`/`text`/`blob`) keeps the C boundary in one place. Public surface: `connect`, `close`, `exec`, `write`, `query`, `transaction`. Path is injectable at init for test isolation; `Database.shared` defaults to `~/Library/Application Support/ListenToMe/store.sqlite`.
- **`Core/Storage/Migrations.swift`** — schema-versioned migrations driven by SQLite's `PRAGMA user_version`. Each step runs in its own `BEGIN IMMEDIATE` transaction so a crash mid-step rolls back cleanly; idempotent across launches. v1 schema lands three tables (`scratchpad`, `snippets`, `transforms`) for the first wave of stores migrated; future migrations append numbered steps so partially-rolled-out builds don't double-migrate.
- **`ScratchpadStore`, `SnippetsStore`, `TransformsStore`** all migrated to SQLite. In-memory shapes and public APIs are unchanged — UI binds to the same `@Published` collections, calls the same `add`/`remove` methods. Per-store legacy migration is identical and idempotent: on first launch with this build, if the legacy `.json` (or `.txt` for scratchpad) exists, it's imported into the SQL table once and renamed `.bak`. DB error → fall back to the legacy file so a transient SQLite problem can never lose user data. SnippetsStore's UNIQUE(keyword) constraint is enforced at the DB level. AppDelegate warms all three at launch so migration runs immediately rather than at first tab visit.

### Tests

- **136 tests, 0 failures across 16 suites** (was 124 in the M5' release):
  - `DatabaseTests` (12) — connect creates file + runs migrations; idempotent connect; close + reconnect preserves data; SQLValue round-trips for text (with unicode + quotes), int/real, null; transaction commits on success / rolls back on throw; UNIQUE(keyword) constraint enforced; scratchpad CHECK(id=1) blocks extra rows; running migrations twice is a no-op.

### Deferred (planned for M6 follow-ups)

- DictionaryStore, CandidateStore, StyleStore, StyleSamplesStore, PagesStore — the five remaining JSON-backed stores. Pattern is established; each is mechanical (~50–100 lines + a numbered migration step). Will land as small focused PRs.
- `*.json` cleanup: once all stores are migrated, drop the `.bak` files via a one-time cleanup pass (after a multi-version cooling-off period so a downgrade can still recover).

### Added — Streaming partial transcripts (M5')

- **Live partial transcripts during recording.** When the user holds the hotkey, a small floating preview above the pill shows what whisper has transcribed so far, updating ~every 1.5 s. Off by default; opt in via Settings → AI Cleanup → Whisper Model → "Live partial transcripts" (requires Linked engine).
- New `Core/PartialTranscriber.swift` drives the polling loop with sane safety rails: 1.5 s cadence (sub-second whisper passes hallucinate), 2.0 s warmup before the first pass, `WhisperLib.isBusy` skip-if-busy gate (no queueing), and a hallucination filter that drops well-known whisper-on-silence outputs (`[BLANK_AUDIO]`, `[SILENCE]`, `Thank you.`, `you`, etc.) before they hit the UI.
- New `AudioRecorder.start(accumulateSamples:)` and `currentSamples()` API — in-memory rolling Float32 sample accumulator capped at 30 s (whisper-base's receptive window). nil when not requested → zero allocation in the common case.
- `AppState.partialText` is auto-cleared by the existing phase-change Combine sink when phase leaves `.recording` / `.transcribing`, so the partial doesn't bleed into the `.success` UI.

### Added — Linked whisper engine + Core ML acceleration (M5)

- **In-process libwhisper engine.** New opt-in transcription path that calls `whisper_full` directly via a Clang module (`CWhisper`) wrapping the bundled `libwhisper.1.dylib`. Eliminates the HTTP round-trip / multipart encoding the warm-server path uses; required infrastructure for streaming partial transcripts (whisper-server is request/response only). One `whisper_context` per app session, lazy-initialized on first transcribe and reused. Settings → AI Cleanup → Whisper Model → **Transcription engine** → "Linked (in-process, supports streaming)". Default stays `.server` so existing users see no behaviour change until they opt in.
- **Core ML encoder support.** `setup.sh` now builds `libwhisper` with `-DWHISPER_COREML=1 -DWHISPER_COREML_ALLOW_FALLBACK=1` and downloads `ggml-base.en-encoder.mlmodelc.zip` (~50 MB) into `~/Library/Application Support/ListenToMe/models/`. When present, the encoder runs on the Apple Neural Engine for ~2× speedup; missing package falls back silently to Metal/CPU encoder. `WhisperModelManager.coreMLPackageInstalled` exposes the status.
- **Bundled `libwhisper.coreml.dylib`** alongside `libwhisper.1.dylib`. Both rpath-rewritten to `@loader_path` and adhoc-signed to match the existing dylib bundle pattern.

### Changed

- `WhisperRunner.transcribe` routes per `Preferences.transcriptionEngine` (`.server` default / `.linked` opt-in). Both engines fall back to the CLI subprocess on any error so the user always gets a transcript. The linked engine doesn't tear down its context on failure — model load is shared across calls; one bad call shouldn't re-pay it.
- `applicationWillTerminate` now also calls `WhisperLib.shared.shutdown()` to free the `whisper_context` cleanly on quit.

### Tests

- **111 tests, 0 failures** (was 102 in v0.13.0):
  - `TranscriptionEngineTests` (7) — default `.server`, persistence round-trip, all-cases distinct raw values, label sanity, default-marker in label, streaming-capability mention in linked label, fallback to `.server` on unknown raw value
  - `WhisperModelManagerCoreMLTests` (2) — `coreMLPackageURL` path semantics, `coreMLPackageInstalled` returns a Bool without crashing

### Deferred

- **Streaming partial transcripts** — the linked engine makes them possible, but the UX (avoiding hallucinations on sub-second chunks, reading a growing WAV, busy-gate coordination with the final transcribe) wants its own focused PR. Tracked as a follow-up.

## [v0.14.8] — 2026-06-17

### Changed

- **Dictionary casing now covers multi-word and mixed-case terms, not just acronyms.** Any dictionary entry you've cased — "Face ID", "GitHub", "iPhone", "OAuth", "KYC" — is rewritten to that exact casing wherever it appears ("face id" → "Face ID"). Multi-word terms match across flexible whitespace; longest terms win first; all-caps acronyms keep their stopword/length guard.

### Tests

- New cleanup eval fixture (`false-start-restart`) measuring whether the model drops an abandoned self-correction ("it's recurring it's requiring" → "it's requiring").

## [v0.14.7] — 2026-06-17

### Added

- **Dictionary-seeded acronym casing.** All-caps dictionary entries (e.g. `KYC`, `API`, `SDK`) are now force-uppercased wherever they appear in a transcript — "v2 kyc process" → "v2 KYC process". Deterministic and engine-independent. Guarded against digits/mixed-case entries and a stopword list so a stray all-caps "IT" can't uppercase every "it".

## [v0.14.6] — 2026-06-12

### Added

- **Collapse stuttered repeated words.** Dictating "the gesture detector detector" now yields "the gesture detector". Runs before cleanup, engine-independent. Preserves emphatic/grammatical doubles ("very very", "had had", "no no"), repeated digits, and never collapses across punctuation.

### Tests

- New cleanup eval fixture (`doubled-word-and-garble`) measuring whether the cleanup model catches a doubled word + a spurious possessive ("there's"→"there") in isolation.

## [v0.14.5] — 2026-06-12

### Added

- **Spoken "plus" → "+" in version build metadata and the C++ idiom.** "release 1.0.29 plus 230" → `1.0.29+230`; "C plus plus" → `C++`. High-precision: the left side must be a dotted version, so ambiguous prose ("2 plus 2", "plus one") is left as words.

## [v0.14.4] — 2026-06-12

### Added

- **Spoken "dot" → "." for file names, domains, and decimals.** Dictating "readme dot md" now yields `readme.md`; "example dot com" → `example.com`; "3 dot 14" → `3.14`. High-precision (only known extensions/TLDs, so "the dot product" is untouched); determiner-aware so "all the dot md files" → "all the .md files" while "the readme dot md" → "the readme.md".

## [v0.14.3] — 2026-06-12

User-facing arc since v0.13.0 (waves 5–8 plus polish). Bundle build 30.

### Added

- **Parakeet TDT v3 transcription** (FluidAudio, Core ML / Apple Neural Engine) as a selectable engine alongside whisper.cpp — ~0.09 s/utterance. Opt-in **dictionary biasing** (CTC word-spotting) favors your saved terms.
- **In-app A/B benchmark** (Settings → Privacy → Engine Benchmark): read-aloud cards scoring WER + latency, Whisper vs Parakeet.
- **On-device Gemma 4 cleanup** via llama.cpp — transcripts never leave the Mac. Light/Medium/High intensity, a meaning-guard (content-word recall / hallucination checks) replacing the old heuristic, and a cleanup-gate that skips already-clean text. Cloud Claude (direct API or CLI) remains an alternative.
- **Tabbed Settings** (General / Dictation / Models / Privacy / About) and a **Liquid Glass** UI pass on macOS 26 (graceful fallback on 14–25).
- **History pagination** (windowed / infinite scroll).
- **Delete downloaded models** to reclaim disk space (Whisper, Gemma, Parakeet) — re-downloadable anytime.
- **Privacy → Permissions toggles**, both default off: *Context-aware tone* (reads active browser tab URL) and *Voice commands* (`open`/`shell`/`log to today`).

### Fixed / Security

- **Stable code signing** (`scripts/resign-stable.sh`): builds are re-signed with a Developer ID / Apple Development identity so macOS TCC **persists permission decisions** instead of re-prompting on every dictation.
- The launch-time `which claude` probe now runs only when cloud cleanup is selected — removes a spurious "network volume" permission prompt for on-device users.
- Dictation into secure (password) fields is blocked (`SecureInput` guard).

## [v0.13.0] — 2026-05-09

## [v0.13.0] — 2026-05-09

The "Wispr-parity + foundations" release. Three months of work in three days, captured across PRs #18 / #19 / #20 / #21.

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
