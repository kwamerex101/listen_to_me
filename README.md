# ListenToMe

Local-first voice → text Mac app. Hold a hotkey anywhere on macOS, speak,
release, and the cleaned transcript pastes into whatever app you were using.

Audio is transcribed offline by [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
Optional cleanup is handled by Claude through a local
[claude_local_api](https://github.com/kwamerex101/claude_local_api) wrapper
that reuses your existing Claude Code subscription — no separate Anthropic
API key required. Cleanup only fires above a configurable word threshold,
so short utterances stay raw and fast.

Inspired by Wispr Flow; built native in SwiftUI + AppKit so the menu-bar
pill, dynamic notch UI, and global hotkey behave like first-class macOS.

## Features

- **Push-to-talk hotkey** anywhere on macOS — Fn + ⌘ default; switchable to
  Fn + ⌥, ⌃ + ⌘, or ⌃ + ⌥ in Settings
- **Floating dynamic-island-style pill** at the bottom of the screen — tiny
  when idle, expands to a recording bar with X (cancel) and ⏹ (stop) controls
- **Smart AI cleanup** — never / only > 20 words / only > 50 words / always.
  Filler words removed (um, uh, like, you know), punctuation + capitalization
  fixed, voice preserved (no rewriting). Falls back to raw on any cleanup
  failure so dictation never breaks
- **Custom dictionary** — proper nouns, jargon, product terms get fed to
  whisper.cpp's `--prompt` so transcription matches your spelling
- **Snippets** — keyword → expansion replacement before cleanup
  (`my email` → your address)
- **Voice commands** — say `log to today: …`, `open Chrome`, or `shell: git status`
  to bypass paste and run an action
- **Permission card** that animates out of the pill when Accessibility is missing,
  springs back in when granted
- **Audible + haptic feedback** — Pop on press, Tink on release, Bottle on cancel,
  configurable in Settings; haptics fire on Force Touch trackpads
- **Dashboard** — words per minute (with percentile gauge), AI fixes made
  (filler + dictionary hits), total words dictated (+month-over-month delta),
  per-app usage breakdown, 16-week activity heatmap with current-streak highlight
- **Auto-start** — launch at login + auto-spawn `claude_local_api` so the
  pipeline is up after every reboot
- **Light + dark mode** — semantic colors throughout

## Setup

Requirements: macOS 14+, Xcode 15+, Homebrew, an Apple Silicon Mac
(model performance is fine on Intel but Metal backend is built for arm64).

```bash
git clone https://github.com/kwamerex101/listen_to_me.git ListenToMe
cd ListenToMe
./scripts/setup.sh        # installs xcodegen, builds whisper.cpp, downloads model, bundles dylibs
./scripts/build.sh        # generates xcodeproj and builds Debug
./scripts/install.sh      # copies build/Build/Products/Debug/ListenToMe.app to /Applications
```

`setup.sh` is idempotent — re-run it whenever you want to refresh whisper.cpp.

To use the AI cleanup feature, also run `claude_local_api` somewhere — easiest
is to clone it side-by-side at `/Users/<you>/Projects/claude_local_api` and
let ListenToMe auto-spawn it on launch. See that repo's README.

## First run

1. Launch from `/Applications/ListenToMe.app` (or build output)
2. Permission card pops up — click **Open Settings**, toggle ListenToMe on
   under Privacy & Security → Accessibility, then return to the app
3. macOS will prompt for Microphone access on first hotkey press
4. Click into any text field; **hold Fn + ⌘**; speak; release
5. Open the menu-bar icon → "Open ListenToMe…" (⌘,) for the main window

## Scripts

| Script | What it does |
|---|---|
| `./scripts/setup.sh` | Installs xcodegen, clones + builds whisper.cpp, downloads `ggml-base.en` model (~148 MB), bundles whisper-cli + dylibs into Resources with `install_name_tool` rewriting rpath to `@loader_path` |
| `./scripts/build.sh` | `xcodegen generate` → `xcodebuild -configuration Debug` |
| `./scripts/install.sh` | Quits any running copy, then `ditto`s the freshly built `.app` into `/Applications/ListenToMe.app` |

## How it works

```
Press Fn + ⌘
   ↓
AVAudioEngine captures mic to /tmp/listentome-<uuid>.wav at 16 kHz mono
   ↓
Release Fn + ⌘
   ↓
whisper.cpp transcribe (LOCAL, with --prompt = your dictionary words)
   ↓
Snippet expansion (regex word-boundary replace)
   ↓
[if word count > threshold] → POST /subprocess/query on claude_local_api → cleanup
   ↓
[if voice command prefix matches] → CommandRouter execute → skip paste
   ↓
NSPasteboard.setString + simulated ⌘V into the frontmost app
   ↓
HistoryStore records timestamp / raw / final / duration / app bundle id
```

Audio never leaves the machine. Only text — and only when above the
configured cleanup threshold — flows out via `claude_local_api` to Anthropic.

## Project layout

```
ListenToMe/
├── project.yml                          # xcodegen config
├── scripts/{setup,build,install}.sh
├── ListenToMe/
│   ├── ListenToMeApp.swift              # @main + AppDelegate orchestration
│   ├── Info.plist
│   ├── ListenToMe.entitlements          # mic input + (no sandbox in v1)
│   ├── Core/
│   │   ├── HotkeyMonitor.swift          # CGEventTap on the chosen modifier combo
│   │   ├── AudioRecorder.swift          # AVAudioEngine → 16kHz WAV + RMS levels
│   │   ├── WhisperRunner.swift          # Process invocation of bundled whisper-cli
│   │   ├── ClaudeClient.swift           # HTTP client for claude_local_api + sanitizer
│   │   ├── CommandRouter.swift          # voice-command parsing + execution
│   │   ├── Paster.swift                 # NSPasteboard + simulated ⌘V
│   │   ├── Haptics.swift, SoundCue.swift, LaunchAtLogin.swift, APIServer.swift
│   ├── State/
│   │   ├── AppState.swift               # phase / level / interaction callbacks
│   │   ├── Preferences.swift            # cleanup mode, hotkey binding, sound toggle
│   │   ├── HistoryStore.swift           # JSON-persisted transcripts + stats
│   │   ├── DictionaryStore.swift, SnippetsStore.swift
│   ├── UI/
│   │   ├── PillWindow.swift, PillView.swift, WaveformView.swift
│   │   ├── MenuBarController.swift, MainWindowController.swift, MainView.swift
│   │   ├── SidebarView.swift, HomeView.swift, DashboardView.swift
│   │   ├── DictionaryView.swift, SnippetsView.swift, SettingsView.swift
│   │   ├── EmptyStateView.swift, PressableStyle.swift
│   └── Resources/                       # whisper-cli + dylibs (bundled by setup.sh, gitignored)
└── vendor/whisper.cpp                   # cloned by setup.sh, gitignored
```

## Configuration

User preferences live in UserDefaults under the `wf.*` namespace and are
adjustable from the in-app Settings tab:

| Setting | Values |
|---|---|
| `cleanupMode` | Never / Smart > 20 words (default) / Smart > 50 / Always |
| `hotkeyBinding` | `fnCmd` (default) / `fnOpt` / `ctrlCmd` / `ctrlOpt` |
| `soundEnabled` | Bool, default `true` |
| Launch at Login | macOS-managed via `SMAppService.mainApp` |

Persistent data lives at `~/Library/Application Support/ListenToMe/`:

- `models/ggml-base.en.bin` — the Whisper model
- `history.json` — every transcript (timestamp, raw, final, duration, app bundle id)
- `dictionary.json` — custom vocabulary
- `snippets.json` — keyword → expansion pairs

## Roadmap

Built but **coming soon** (placeholder pages in the sidebar):

- **Style** — per-app writing styles with custom system prompts (formal in
  Mail, casual in Slack, terse in Xcode)
- **Transforms** — chained cleanup pipelines (clean → bulletize, clean →
  translate, etc.)
- **Scratchpad** — long-form dictation workspace inside the app

Other not-yet-shipped:

- Recover-dismissed-transcript button on Home
- First-run onboarding tour
- Full hotkey recorder (today: 4 presets only)
- Language picker + extra Whisper model downloads
- App icon, Developer-ID signing, notarization, DMG packaging, Sparkle auto-update

## License

Personal project. Not currently licensed for redistribution.
