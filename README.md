<div align="center">

<img src="ListenToMe/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="ListenToMe app icon" width="128" height="128">

# ListenToMe

![License](https://img.shields.io/badge/License-MIT-yellow.svg)
![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)

**Free, local-first alternative to Wispr Flow for macOS.**

</div>

Hold a hotkey
anywhere, speak, release — the cleaned transcript pastes into whatever app you
were using. No subscription, no cloud-mandatory dependency, no audio leaving
your machine.

**Speech-to-text** runs fully offline, with two selectable engines:
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) (default) and
[NVIDIA Parakeet TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
on the Apple Neural Engine (via [FluidAudio](https://github.com/FluidInference/FluidAudio)) —
~5–7× faster per utterance at parity accuracy. An in-app A/B benchmark
(Settings → Models) lets you compare them on your own voice.

**Cleanup** (grammar, filler removal, punctuation, casing) is optional and
also runs on-device by default: a local **Gemma 4** model via
[llama.cpp](https://github.com/ggml-org/llama.cpp) (E2B, or 12B on 16 GB+
Macs). No transcript leaves the device. You can switch the cleanup engine to
Claude — either your installed [Claude Code CLI](https://claude.ai/code)
(reusing your subscription, no API key) or the direct Anthropic API with
prompt caching. Cleanup has Light / Medium / High intensity levels and a
meaning-preservation guard that falls back to the raw transcript rather than
ship a rewrite that dropped or invented words.

Built native in SwiftUI + AppKit so the menu-bar pill, dynamic notch UI, and
global hotkey behave like first-class macOS citizens.

## Highlights vs Wispr Flow

| Capability | Wispr Flow | ListenToMe |
|---|---|---|
| **STT** | Cloud-only ensemble | **Local, offline** — whisper.cpp **or** Parakeet TDT v3 (Neural Engine) |
| **Cleanup** | Cloud LLM | **On-device Gemma 4** (default) OR Claude CLI / direct Anthropic API |
| **Audio leaves the device** | every clip | **never** |
| **Cleanup can stay on-device** | no | **yes** (local Gemma) |
| **Cleanup intensity levels** (None/Light/Medium/High) | ✅ | ✅ |
| **Meaning-preservation guard** (reject rewrites that change content) | — | ✅ |
| **In-app ASR A/B benchmark** | — | ✅ (WER + latency, your voice) |
| **Backtrack** ("actually, …" rewrites the prior paste) | ✅ | ✅ |
| **Context awareness** (per-app tone + browser URL) | ✅ | ✅ |
| **Code-aware tokenization** (camelCase/snake_case in editors) | ✅ | ✅ |
| **Auto-personal-dictionary** | ✅ | ✅ (mined from history + retype probes) |
| **Edge-dockable Flow Bar** (drag the pill anywhere, persist) | ✅ | ✅ |
| **Auto-shrink to a dot** after sustained idle | ✅ | ✅ (5 s) |
| **Cancel mid-transcribe / mid-cleanup** | ✅ | ✅ |
| **VoiceOver labels + reduce-motion gating** | partial | ✅ |
| **Hands-free voice activation** (always-listening) | ✅ | ❌ — would defeat 0 % idle CPU |
| **Idle resource footprint** | ~800 MB RAM, ~8 % CPU | **~25 MB RSS, 0.0 % CPU** |
| **Works offline** | no | yes (transcription always; cleanup with local Gemma) |
| **Apple Notes output destination** | — | ✅ (append / new note / daily note; local Apple Events only) |
| **First-run onboarding** (5-screen walkthrough + model download) | — | ✅ |

## Setup

Requirements: macOS 14+, Xcode 15+, Homebrew, an Apple Silicon Mac (Metal
backend; Intel works with degraded transcription speed).

```bash
git clone https://github.com/kwamerex101/listen_to_me.git ListenToMe
cd ListenToMe
./scripts/setup.sh        # installs xcodegen, builds whisper.cpp, downloads + SHA-verifies model, bundles binaries + dylibs
./scripts/build-llama.sh  # builds libllama (Gemma cleanup) + isolates its ggml from whisper's; syncs headers
./scripts/build.sh        # generates xcodeproj and builds Debug
./scripts/release.sh      # builds Release + DMG (hardened runtime, arm64)
```

`build-llama.sh` is required for the on-device Gemma cleanup engine — it
clones + builds llama.cpp and renames its ggml dylibs (`-lt` suffix) so they
coexist with whisper's older ggml in the same bundle. Both `setup.sh` and
`build-llama.sh` produce gitignored build artifacts and are idempotent.

The Gemma cleanup model (GGUF, ~3 GB E2B) and the Parakeet ASR model
(~600 MB Core ML) are **downloaded in-app on first use** from Settings →
Models — not bundled. Parakeet ships via the FluidAudio Swift Package
(the project's only SPM dependency).

To install the Release build:

```bash
cp -R build-release/Build/Products/Release/ListenToMe.app /Applications/
xattr -dr com.apple.quarantine /Applications/ListenToMe.app   # skip Gatekeeper warning
open -a ListenToMe
```

`setup.sh` is idempotent and SHA-256-verifies the bundled model on every run —
a tampered or corrupt local copy gets auto-replaced.

AI cleanup is **optional**. Without it the app works perfectly — transcription
is fully offline; only the grammar / filler-word / casing polish step is
skipped.

The cleanup **engine** is chosen in Settings → Models → On-Device Polish:

- **On-device (Gemma)** — a local Gemma 4 model via llama.cpp. Fully offline;
  the transcript never leaves the device. Picking this is a privacy contract:
  if the model is missing the dictation keeps its raw text rather than
  silently falling back to the cloud.
- **Claude (cloud)** — uses the cloud **backend** selected in Settings →
  Dictation → AI Cleanup → Cloud backend:
  - **Auto** (default) — direct Anthropic API when an `sk-ant-…` key is saved
    in the Keychain, otherwise the `claude` CLI subprocess
  - **CLI** — always the `claude` CLI (reuses your Claude Code subscription;
    latency dominated by Node startup, ~1.5–3 s)
  - **API** — always the direct path, ~250–500 ms with prompt caching

Cleanup **intensity** (Light / Medium / High) controls how aggressively it
edits — Light is structural-only and keeps every content word. A
content-word **meaning guard** rejects any result that dropped or invented
words and falls back to the raw transcript. Cleanup also **skips already-clean
text** (no fillers, punctuated, capitalized) under the Smart modes, saving a
model call and avoiding degradation.

To disable cleanup entirely, set Mode to "Never" in Settings → Dictation.

## First run

1. Launch from `/Applications/ListenToMe.app`. Builds are signed with a stable
   identity when one is in your keychain (Developer ID or Apple Development —
   see `scripts/resign-stable.sh`), which lets macOS **remember** your
   permission choices. Without a signing identity the build falls back to
   ad-hoc — still runs, but macOS re-prompts for permissions each launch (and
   may show a Gatekeeper warning unless you ran `xattr -dr com.apple.quarantine`
   above). Not notarized either way.
2. Permission card pops up — click **Open Settings**, toggle ListenToMe on
   under Privacy & Security → Accessibility, then return to the app.
3. macOS prompts for Microphone access on first hotkey press. You may also see
   one-time prompts for media/Photos — these are AVFoundation side effects of
   mic capture; the app never reads that content, so **Don't Allow** is safe.
   (After switching from an older ad-hoc build to a signed one, re-grant
   Microphone + Accessibility once — the signing identity changed.)
4. Click into any text field; **hold Fn + ⌘**; speak; release.
5. Open the menu-bar icon → "Open ListenToMe…" (⌘,) for the main window.

## How it works

```
Press Fn + ⌘
   ↓
AVAudioEngine captures mic to ${TMPDIR}/listentome-<uuid>.wav at 16 kHz mono
   ↓
Release Fn + ⌘
   ↓
Transcription engine (Settings → Models → Transcription):
   • Parakeet — one-shot Core ML / ANE (FluidAudio); ~0.09 s/utterance
   • Whisper Server — persistent whisper-server subprocess (default)
   • Whisper Linked — in-process whisper.cpp (supports live partials)
   └─→ any engine falls back to the whisper-cli subprocess on error
   ↓
Backtrack check ("actually, …" / "scratch that, …") → if matched and a
recent paste token is still valid, rewrite the prior paste in place
   ↓
Voice-command interception (`open Chrome`, `shell: …`)
   ↓
Voice-edit transforms (comma, period, scratch that, new paragraph)
   ↓
Snippet expansion (regex word-boundary replace)
   ↓
[if Smart-mode gate passes AND text isn't already clean] → cleanup
        engine: local Gemma 4 (llama.cpp) OR Claude (direct API / CLI)
        with system prompt: CONTEXT (app, category, browser URL) +
        per-app STYLE (tone hint) + vocabulary + base prompt (default OR
        code-mode for editors/terminals) + intensity instruction
   └─→ MeaningGuard: reject + keep raw if content words dropped/invented
   ↓
Secure-input guard: never paste into a password field
   ↓
NSPasteboard.setString + simulated ⌘V into the frontmost app
   ↓
Three-gate paste-replace if cleanup arrives later: staleness ≤ 30 s,
frontmost-bundle match, pasteboard changeCount unchanged
   ↓
HistoryStore appends one NDJSON line (constant-time)
```

Audio never leaves the machine. Text only leaves the device when cleanup is
enabled and runs above the configured threshold; the destination is whichever
backend is selected.

## Pill states

| State | Visual | What you can do |
|---|---|---|
| Idle (calm) | Small 48×12 dot | Hover to expand; drag to move |
| Idle (shrunk) | 10×10 dot after 5 s of true idle | Hover to wake |
| Recording | Red waveform + Cancel/Stop buttons | Cancel (X) or release hotkey |
| Transcribing | Spinner + "Transcribing…" + Cancel | Cancel (X) |
| Cleaning / Polishing | Sparkle + status + Cancel | Cancel (X) or click pill to edit |
| Success | Green checkmark | Click to open the inline correction popover |
| Correcting | Pill goes neutral; popover takes focus | ⌘↵ Apply, Esc Cancel, mic to voice-replace |
| Suggestion | App-tone banner | Keep / Dismiss / 8 s timeout |
| Error | Orange warning | Auto-clears |

The pill is **draggable** — grab and reposition anywhere on screen; position
persists per launch. Reset to default from Settings → General → Pill position.

VoiceOver reads each phase aloud; reduce-motion suppresses the idle breath,
recording heartbeat, and 30 Hz waveform animations.

## Voice gestures

- **Punctuation**: `comma`, `period`, `question mark`, `exclamation point`,
  `new line`, `new paragraph`
- **Verbal undo**: `scratch that` drops the previous sentence; `scratch that`
  alone aborts the dictation
- **Backtrack** (Wispr-style): start your next dictation with
  `actually, …` / `scratch that, …` / `wait, change that to …` / `i meant …`
  to rewrite the previous paste in place via Claude
- **Voice commands** (opt-in — Settings → Privacy → Permissions): `open Chrome`,
  `open Safari`, `open <App>`, `shell: <command>`, `log to today: <text>`. Off
  by default because `log to today` writes to your Documents folder and `shell`
  runs a terminal command.
- **Code mode** (auto): when the target app is a code editor or terminal
  (Cursor, Xcode, VS Code, iTerm, Warp, Zed, Hyper, IntelliJ, …), the
  cleanup prompt skips sentence-case and recognizes
  `camel case <words>` / `pascal case <words>` / `snake case <words>` /
  `kebab case <words>` / `screaming snake case <words>`

## Settings

Settings is organized into five tabs (chip bar):

| Tab | Setting | Values / behavior |
|---|---|---|
| **General** | Dictation hotkey | Fn + ⌘ (default) / Fn + ⌥ / ⌃ + ⌘ / ⌃ + ⌥ |
| | Theme | System / Light / Dark |
| | Sound cues | toggle |
| | Pill position | Custom (drag) or default; Reset button |
| | Launch at login | macOS-managed via `SMAppService.mainApp` |
| | Accessibility | Status + Open System Settings shortcut |
| **Dictation** | Microphone | System default or a specific input device |
| | Max recording duration | 30–600 s (default 120) |
| | AI cleanup — Mode | Never / Smart > 20 words (default) / Smart > 50 / Always |
| | AI cleanup — Intensity | Light (default) / Medium / High |
| | Cloud backend | Auto / CLI subprocess / Direct Anthropic API |
| | Anthropic API key | Stored in macOS Keychain |
| | Cleanup timeout | 5–60 s (default 20) |
| | Output destination | Active app (paste, default) / Apple Notes (append / new note / daily note) / Clipboard |
| **Models** | Transcription engine | Whisper Server (default) / Whisper Linked / Parakeet (ANE) |
| | Whisper model | Status + download (base 148 MB … large-turbo 1.6 GB), SHA-256 verified |
| | Accuracy / Live partials | Whisper Linked only (beam search, streaming) |
| | Parakeet model | Status + download (~600 MB Core ML) |
| | (any downloaded model) | **Delete** to reclaim disk space — re-downloadable anytime |
| | On-Device Polish — engine | Claude (cloud) / On-device Gemma |
| | Gemma model | Gemma 4 E2B (default) / 12B (≥16 GB RAM); status + download |
| | Engine Benchmark (A/B) | Read-aloud cards; WER + latency, Whisper vs Parakeet |
| **Privacy** | History retention | 0–365 days (default 90; 0 = forever); Apply purges immediately |
| | Encrypt history at rest | AES-GCM toggle (one-time re-encrypt of `history.ndjson`) |
| | Context-aware tone | Opt-in (default off); reads active browser tab URL to match cleanup tone |
| | Voice commands | Opt-in (default off); enables `open`/`shell`/`log to today` |
| | Diagnostics log | Off by default; rotated at 1 MB; never includes transcripts |
| **About** | Version | from the bundle |
| | Processing | on-device note |

## Persistent data

Lives at `~/Library/Application Support/ListenToMe/`:

| File | Contents |
|---|---|
| `models/ggml-*.bin` | Whisper model(s), SHA-256-verified on every launch |
| `llm/gemma-4-*-it-Q4_K_M.gguf` | On-device Gemma cleanup model (downloaded in-app) |
| `parakeet/` | Parakeet TDT v3 Core ML model bundles (downloaded in-app) |
| `history.ndjson` | Append-only line-delimited transcripts; optionally AES-GCM-encrypted at rest; auto-migrated from legacy `history.json.bak` once on first launch |
| `dictionary.json` | Custom + auto-promoted vocabulary |
| `dictionary-candidates.json` | Pending retype + history-mined candidates (3 distinct occurrences → auto-promote) |
| `snippets.json` | Keyword → expansion pairs |
| `transforms.json` | Named cleanup prompts |
| `style.json`, `style-samples.json` | Per-app inferred / accepted tones, rolling sample window |
| `retype-debug.log` | Diagnostic-only; off by default |

The Anthropic API key (when set) lives in the macOS Keychain under service
`com.rexdanquah.listentome`, account `anthropic_api_key`.

## Project layout

```
ListenToMe/
├── project.yml                     # xcodegen config (+ FluidAudio SPM dep)
├── scripts/{setup,build-llama,build,release}.sh
├── ListenToMe/
│   ├── ListenToMeApp.swift         # @main + AppDelegate orchestration
│   ├── Info.plist
│   ├── ListenToMe.entitlements     # mic input + AppleEvents + library-validation carve-out
│   ├── Core/
│   │   ├── HotkeyMonitor.swift     # CGEventTap on the chosen modifier combo
│   │   ├── AudioRecorder.swift     # AVAudioEngine → 16 kHz WAV + RMS levels
│   │   ├── WhisperRunner.swift     # engine router (Parakeet / server / linked) → whisper-cli fallback
│   │   ├── WhisperServer.swift     # persistent whisper-server subprocess + multipart HTTP
│   │   ├── WhisperLib.swift        # in-process whisper.cpp (linked engine, streaming)
│   │   ├── WhisperModelManager.swift  # SHA-256 verify + download
│   │   ├── ParakeetEngine.swift    # Parakeet TDT v3 via FluidAudio (Core ML / ANE)
│   │   ├── ClaudeClient.swift      # cleanup router: local Gemma / direct API / claude CLI; sanitize
│   │   ├── LocalLLMEngine.swift    # on-device Gemma via the CLlamaBridge shim
│   │   ├── LLMModelManager.swift   # Gemma GGUF download + status
│   │   ├── CleanupMetrics.swift    # content-word recall / hallucination / Jaccard
│   │   ├── MeaningGuard.swift      # reject cleanups that change content → keep raw
│   │   ├── CleanupGate.swift       # skip cleanup on already-clean text
│   │   ├── WERCalculator.swift     # benchmark WER (normalized)
│   │   ├── SecureInput.swift       # block insertion into password fields
│   │   ├── AppContext.swift, Backtrack.swift, HistoryDictionaryMiner.swift
│   │   ├── CommandRouter.swift, VoiceEditor.swift
│   │   ├── Paster.swift            # NSPasteboard + simulated ⌘V + 3-gate replace + secure-input guard
│   │   ├── Keychain.swift, Haptics.swift, SoundCue.swift, LaunchAtLogin.swift
│   │   ├── ToneInferencer.swift, RetypeDiffer.swift
│   ├── CWhisper/                   # Clang module map exposing whisper.cpp's C API
│   ├── CLlama/                     # llama.cpp headers (gitignored, synced by build-llama.sh)
│   ├── CLlamaBridge/               # C++ shim — keeps llama's ggml out of the Swift module graph
│   ├── State/
│   │   ├── AppState.swift          # phase / level / interaction callbacks
│   │   ├── Preferences.swift       # engines, cleanup mode/intensity/backend, hotkey, retention, …
│   │   ├── HistoryStore.swift      # NDJSON append-only + retention + optional AES-GCM
│   │   ├── DictionaryStore.swift, SnippetsStore.swift, CandidateStore.swift
│   │   ├── StyleStore.swift, StyleSamplesStore.swift, TransformsStore.swift
│   ├── UI/
│   │   ├── PillWindow.swift, PillView.swift, WaveformView.swift
│   │   ├── CorrectionWindow.swift  # inline edit popover
│   │   ├── MenuBarController.swift, MainWindowController.swift, MainView.swift
│   │   ├── SidebarView.swift, HomeView.swift, HistoryView.swift, RecordRow.swift
│   │   ├── DictionaryView.swift, SnippetsView.swift, StyleView.swift
│   │   ├── SettingsView.swift      # five-tab layout
│   │   ├── BenchmarkView.swift     # in-app ASR A/B benchmark
│   │   ├── TransformsView.swift
│   │   ├── DesignTokens.swift, Motion.swift, PressableStyle.swift, HoverableRow.swift
│   └── Resources/                  # whisper-cli/-server + dylibs (setup.sh); llm/ (build-llama.sh); gitignored
├── ListenToMeTests/                # XCTest target
└── vendor/{whisper.cpp,llama.cpp}  # cloned by setup.sh / build-llama.sh, gitignored
```

## Tests

Pure-logic tests live in `ListenToMeTests/`:

```bash
xcodebuild test -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'
```

Or in Xcode: ⌘U.

Coverage is focused on the deterministic, side-effect-free helpers: voice
editing transforms, snippet expansion, tone inference, retype diffing,
backtrack parsing, history mining, app context classification, history NDJSON
round-trip, ClaudeClient prompt sanitization, the cleanup metrics +
meaning guard + messiness gate, secure-input role detection, and the
benchmark WER calculator. UI behavior (pill states, drag-to-reposition,
cancel-mid-pipeline) is validated manually per the project's "no UI snapshot
tests" stance.

Two model-backed harnesses are gated behind env flags so they don't run in
normal CI (they load multi-GB models and are slow / nondeterministic):

```bash
# Cleanup quality eval — scores Gemma cleanup on raw→ideal fixtures
TEST_RUNNER_LTM_RUN_EVAL=1 xcodebuild test \
  -only-testing:ListenToMeTests/CleanupEvalTests \
  -project ListenToMe.xcodeproj -scheme ListenToMe -destination 'platform=macOS'
```

The ASR A/B comparison (Whisper vs Parakeet) is interactive — run it from
Settings → Models → Engine Benchmark by reading the cards aloud.

## Security & privacy

See [SECURITY.md](SECURITY.md) for the full posture: hardened runtime,
adhoc-signed bundle, library validation, entitlements, subprocess safety,
pasteboard 3-gate model, NDJSON retention, model SHA-256 verification, and
how to re-verify after a build.

## Author

Theophilus RexDanquah — [rexdanquah.dev](https://rexdanquah.dev)

## License

Released under the [MIT License](LICENSE).
