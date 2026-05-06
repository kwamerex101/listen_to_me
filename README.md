# ListenToMe

**Free, local-first alternative to Wispr Flow for macOS.** Hold a hotkey
anywhere, speak, release — the cleaned transcript pastes into whatever app
you were using. No subscription, no cloud, no data leaving your machine.

Audio is transcribed offline by [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
Optional cleanup is handled by Claude — the app shells out to your installed
[Claude Code CLI](https://claude.ai/code) (`claude --print`), reusing your
existing Claude Code subscription so no separate Anthropic API key is required. Cleanup only fires above a configurable word threshold, so short
utterances stay raw and fast.

Built native in SwiftUI + AppKit so the menu-bar pill, dynamic notch UI,
and global hotkey behave like first-class macOS citizens.

## Features

The first milestone (v0.7 → v0.11) shipped five capability phases on top of
the core dictation pipeline:

1. **Multi-display anchoring** *(v0.7)* — the pill follows whichever screen
   your cursor is on, re-anchors when you plug or unplug a display
2. **Selection-aware paste** *(v0.8)* — selecting text and dictating replaces
   it; voice `new line` in indented code preserves the indent through cleanup
3. **Auto-learning dictionary** *(v0.9)* — retype a misread the same way 3
   times and the correction promotes itself into your dictionary; no manual
   curation needed for proper nouns / jargon / product terms you actually use
4. **Per-app style tuning** *(v0.10)* — after 20 dictations into the same app,
   ListenToMe infers a tone (`casual` / `formal` / `code` / `markdown`) and
   offers it once via a Keep / Dismiss banner; on Keep, that tone applies to
   all future dictations into that app until you Revert it
5. **UX/UI polish + micro-animations** *(v0.11)* — hover and press feedback on
   every interactive surface, cross-fade tab transitions, silence-dim
   waveform after 5s quiet, tuned pill morph spring, gold flash on dictionary
   auto-promotion

Day-to-day capabilities:

- **Push-to-talk hotkey** anywhere on macOS — Fn + ⌘ default; switchable to
  Fn + ⌥, ⌃ + ⌘, or ⌃ + ⌥ in Settings
- **Floating dynamic-island-style pill** at the bottom of the screen — tiny
  when idle, expands to a recording bar with X (cancel) and ⏹ (stop) controls
- **Smart AI cleanup** — never / only > 20 words / only > 50 words / always.
  Filler words removed (um, uh, like, you know), punctuation + capitalization
  fixed, voice preserved (no rewriting). Falls back to raw on any cleanup
  failure so dictation never breaks
- **Custom dictionary** — proper nouns, jargon, product terms get fed to
  whisper.cpp's `--prompt` so transcription matches your spelling. Includes
  the auto-learning candidate flow described above
- **Snippets** — keyword → expansion replacement before cleanup
  (`my email` → your address)
- **Transforms** — named cleanup prompts you can run on the latest transcript
  (e.g. *Bulletize*, *Translate to Spanish*, *Tighten*)
- **Pages + Scratchpad** — long-form dictation workspaces inside the app
  for when you don't want to dictate into a target editor
- **Voice commands** — say `log to today: …`, `open Chrome`, or `shell: git status`
  to bypass paste and run an action
- **Inline voice editing** — say `comma`, `period`, `question mark`, `exclamation
  point`, `new paragraph`, or `new line` mid-dictation to insert punctuation /
  structure. Say `scratch that` to drop the previous sentence — verbal undo
- **Tap-to-fix correction** — after a paste, click the floating pill within 3
  seconds to open an inline edit field over the pill. Fix a word, hit Return,
  the corrected text replaces what was just pasted in your target app
- **Permission card** that animates out of the pill when Accessibility is missing,
  springs back in when granted
- **Audible + haptic feedback** — Pop on press, Tink on release, Bottle on cancel,
  configurable in Settings; haptics fire on Force Touch trackpads
- **Home dashboard** — total words, average WPM, day streak, today's transcripts
- **Auto-start** — launch at login so the hotkey pipeline is up after every reboot
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

AI cleanup is **optional**. Without it the app works perfectly — transcription
is fully offline via whisper.cpp; only the grammar/filler-word polish step is
skipped. To enable cleanup, install the [Claude Code CLI](https://claude.ai/code)
so the `claude` binary is on your PATH (the app probes `~/.local/bin`,
`~/.npm-global/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`). If you don't
install it, set Cleanup Mode to "Never" in Settings to avoid cleanup errors.

## First run

1. Launch from `/Applications/ListenToMe.app` (or build output). Because the
   app is ad-hoc signed (not notarized), macOS Gatekeeper will block it on
   first launch — right-click the app and choose **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ListenToMe.app
   ```
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
[if word count > threshold] → spawn `claude --print` subprocess → cleanup
   ↓
[if voice command prefix matches] → CommandRouter execute → skip paste
   ↓
NSPasteboard.setString + simulated ⌘V into the frontmost app
   ↓
HistoryStore records timestamp / raw / final / duration / app bundle id
```

Audio never leaves the machine. Only text — and only when above the
configured cleanup threshold — flows out via the `claude` CLI to Anthropic.

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
│   │   ├── ClaudeClient.swift           # spawns `claude` CLI subprocess + sanitizer
│   │   ├── CommandRouter.swift          # voice-command parsing + execution
│   │   ├── Paster.swift                 # NSPasteboard + simulated ⌘V
│   │   ├── Haptics.swift, SoundCue.swift, LaunchAtLogin.swift
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
- `dictionary.json` — custom + promoted vocabulary
- `dictionary-candidates.json` — pending retype-correction candidates
- `snippets.json` — keyword → expansion pairs
- `transforms.json` — named cleanup prompts
- `styles.json` + `style-samples.json` — per-app inferred + accepted tones,
  rolling 50-sample window per app
- `pages.json`, `scratchpad.json` — in-app dictation workspaces

## Roadmap

The first milestone (v0.7 → v0.11) is shipped — multi-display, selection-aware
paste, auto-learning dictionary, per-app style tuning, UX/UI polish.

Likely up next (v0.12+):

- Reduced-motion accessibility fallback
- Cancelled-clip preservation in History (recover the last cancelled
  transcript)
- Live transcription preview overlay on the pill
- First-run onboarding tour
- Full hotkey recorder (today: 4 presets only)
- Language picker + extra Whisper model downloads
- App icon, Developer-ID signing, notarization, DMG packaging, Sparkle auto-update

## License

Released under the [MIT License](LICENSE).
