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

Audio is transcribed offline by [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
Optional cleanup runs through Claude — by default the app shells out to your
installed [Claude Code CLI](https://claude.ai/code) (`claude --print`),
reusing your existing subscription so no separate API key is required. Set an
Anthropic API key in Settings to opt into the direct-API path with prompt
caching for ~5× faster cleanup.

Built native in SwiftUI + AppKit so the menu-bar pill, dynamic notch UI, and
global hotkey behave like first-class macOS citizens.

## Highlights vs Wispr Flow

| Capability | Wispr Flow | ListenToMe |
|---|---|---|
| **STT** | Cloud-only ensemble | **Local whisper.cpp** (offline) |
| **Cleanup** | Cloud LLM | Local CLI subprocess OR direct Anthropic API (Haiku 4.5, prompt-cached) |
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
| **Audio leaves the device** | every clip | **never** |
| **Works offline** | no | yes |

## Setup

Requirements: macOS 14+, Xcode 15+, Homebrew, an Apple Silicon Mac (Metal
backend; Intel works with degraded transcription speed).

```bash
git clone https://github.com/kwamerex101/listen_to_me.git ListenToMe
cd ListenToMe
./scripts/setup.sh        # installs xcodegen, builds whisper.cpp, downloads + SHA-verifies model, bundles binaries + dylibs
./scripts/build.sh        # generates xcodeproj and builds Debug
./scripts/release.sh      # builds Release + DMG (hardened runtime, universal binary)
```

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

Two cleanup backends are supported via Settings → AI Cleanup → Backend:

- **Auto** (default) — direct Anthropic API when an `sk-ant-…` key is saved in
  the Keychain, otherwise the `claude` CLI subprocess
- **CLI** — always the `claude` CLI (preserves the "reuse Claude Code
  subscription" path; latency dominated by Node startup, ~1.5–3 s)
- **API** — always the direct path, ~250–500 ms with prompt caching

If you don't install the Claude Code CLI and don't paste an API key, set
Cleanup Mode to "Never" in Settings to disable cleanup attempts entirely.

## First run

1. Launch from `/Applications/ListenToMe.app`. The app is ad-hoc-signed (not
   notarized); on first launch macOS may show a Gatekeeper warning unless you
   ran the `xattr -dr com.apple.quarantine` step above.
2. Permission card pops up — click **Open Settings**, toggle ListenToMe on
   under Privacy & Security → Accessibility, then return to the app.
3. macOS prompts for Microphone access on first hotkey press.
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
whisper-server (HTTP, persistent — model resident across dictations)
   └─→ falls back to whisper-cli subprocess on any error
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
[if word count > threshold] → Claude cleanup (direct API or CLI subprocess)
        with system prompt: CONTEXT (app, category, browser URL) +
        per-app STYLE (tone hint) + base prompt (default OR code-mode
        for editors/terminals)
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
persists per launch. Reset to default from Settings → Advanced → Pill position.

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
- **Voice commands**: `open Chrome`, `open Safari`, `open <App>`,
  `shell: <command>`, `log to today: <text>`
- **Code mode** (auto): when the target app is a code editor or terminal
  (Cursor, Xcode, VS Code, iTerm, Warp, Zed, Hyper, IntelliJ, …), the
  cleanup prompt skips sentence-case and recognizes
  `camel case <words>` / `pascal case <words>` / `snake case <words>` /
  `kebab case <words>` / `screaming snake case <words>`

## Settings

| Tab | Setting | Values / behavior |
|---|---|---|
| **Shortcuts** | Dictation hotkey | Fn + ⌘ (default) / Fn + ⌥ / ⌃ + ⌘ / ⌃ + ⌥ |
| **AI Cleanup** | Mode | Never / Smart > 20 words (default) / Smart > 50 / Always |
| | Backend | Auto / CLI subprocess / Direct Anthropic API |
| | Anthropic API key | Stored in macOS Keychain |
| **Audio** | Sound cues | toggle |
| **Appearance** | Theme | System / Light / Dark |
| **Whisper Model** | Local model | Status + download (148 MB), SHA-256 verified |
| **System** | Launch at login | macOS-managed via `SMAppService.mainApp` |
| | Accessibility | Status + Open System Settings shortcut |
| **Advanced** | Max recording duration | 30–600 s (default 120) |
| | Cleanup timeout | 5–60 s (default 20) |
| | Diagnostics log | Off by default; rotated at 1 MB |
| | Pill position | Custom (drag) or default; Reset button |
| | History retention | 0–365 days (default 90; 0 = forever); Apply purges immediately |

## Persistent data

Lives at `~/Library/Application Support/ListenToMe/`:

| File | Contents |
|---|---|
| `models/ggml-base.en.bin` | Whisper model, SHA-256-verified on every launch |
| `history.ndjson` | Append-only line-delimited transcripts; auto-migrated from legacy `history.json.bak` once on first launch |
| `dictionary.json` | Custom + auto-promoted vocabulary |
| `dictionary-candidates.json` | Pending retype + history-mined candidates (3 distinct occurrences → auto-promote) |
| `snippets.json` | Keyword → expansion pairs |
| `transforms.json` | Named cleanup prompts |
| `style.json`, `style-samples.json` | Per-app inferred / accepted tones, rolling sample window |
| `pages.json`, `scratchpad.json` | In-app dictation workspaces |
| `retype-debug.log` | Diagnostic-only; off by default |

The Anthropic API key (when set) lives in the macOS Keychain under service
`com.rexdanquah.listentome`, account `anthropic_api_key`.

## Project layout

```
ListenToMe/
├── project.yml                     # xcodegen config
├── scripts/{setup,build,release}.sh
├── ListenToMe/
│   ├── ListenToMeApp.swift         # @main + AppDelegate orchestration
│   ├── Info.plist
│   ├── ListenToMe.entitlements     # mic input + AppleEvents
│   ├── Core/
│   │   ├── HotkeyMonitor.swift     # CGEventTap on the chosen modifier combo
│   │   ├── AudioRecorder.swift     # AVAudioEngine → 16 kHz WAV + RMS levels
│   │   ├── WhisperRunner.swift     # routes via WhisperServer, falls back to whisper-cli
│   │   ├── WhisperServer.swift     # persistent whisper-server subprocess + multipart HTTP
│   │   ├── WhisperModelManager.swift  # SHA-256 verify + download
│   │   ├── ClaudeClient.swift      # direct Anthropic API + claude CLI fallback
│   │   ├── AppContext.swift        # bundleId, category, browser URL via AppleScript
│   │   ├── Backtrack.swift         # "actually, …" trigger parser
│   │   ├── HistoryDictionaryMiner.swift  # mine candidates from history
│   │   ├── CommandRouter.swift, VoiceEditor.swift
│   │   ├── Paster.swift            # NSPasteboard + simulated ⌘V + 3-gate replace
│   │   ├── Keychain.swift          # tiny SecItem wrapper
│   │   ├── Haptics.swift, SoundCue.swift, LaunchAtLogin.swift
│   │   ├── ToneInferencer.swift, RetypeDiffer.swift
│   ├── State/
│   │   ├── AppState.swift          # phase / level / interaction callbacks
│   │   ├── Preferences.swift       # cleanup mode, backend, hotkey, retention, …
│   │   ├── HistoryStore.swift      # NDJSON append-only + days-based retention
│   │   ├── DictionaryStore.swift, SnippetsStore.swift, CandidateStore.swift
│   │   ├── StyleStore.swift, StyleSamplesStore.swift
│   │   ├── TransformsStore.swift, PagesStore.swift, ScratchpadStore.swift
│   ├── UI/
│   │   ├── PillWindow.swift, PillView.swift, WaveformView.swift
│   │   ├── CorrectionWindow.swift  # inline edit popover
│   │   ├── MenuBarController.swift, MainWindowController.swift, MainView.swift
│   │   ├── SidebarView.swift, HomeView.swift
│   │   ├── DictionaryView.swift, SnippetsView.swift, StyleView.swift
│   │   ├── SettingsView.swift, TransformsView.swift, PagesView.swift, ScratchpadView.swift
│   │   ├── DesignTokens.swift, Motion.swift, PressableStyle.swift, HoverableRow.swift
│   └── Resources/                  # whisper-cli, whisper-server, dylibs (bundled by setup.sh, gitignored)
├── ListenToMeTests/                # XCTest target
└── vendor/whisper.cpp              # cloned by setup.sh, gitignored
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
round-trip, and ClaudeClient prompt sanitization. UI behavior (pill states,
drag-to-reposition, cancel-mid-pipeline) is validated manually per the
project's "no UI snapshot tests" stance.

## Security & privacy

See [SECURITY.md](SECURITY.md) for the full posture: hardened runtime,
adhoc-signed bundle, library validation, entitlements, subprocess safety,
pasteboard 3-gate model, NDJSON retention, model SHA-256 verification, and
how to re-verify after a build.

## Author

Theophilus RexDanquah — [rexdanquah.dev](https://rexdanquah.dev)

## License

Released under the [MIT License](LICENSE).
