# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# First-time setup (installs xcodegen, builds whisper.cpp, downloads ~148 MB model)
./scripts/setup.sh

# Generate .xcodeproj and build (Debug)
./scripts/build.sh

# Install to /Applications
./scripts/install.sh
```

`project.yml` is the source of truth for the Xcode project — never edit the `.xcodeproj` directly. After modifying `project.yml`, regenerate with `xcodegen generate`.

There are no automated tests; all testing is manual via the running app.

## Architecture Overview

ListenToMe is a macOS menu-bar dictation app: press-and-hold a global hotkey → record audio → transcribe locally with whisper.cpp → optionally clean up with Claude → paste into the frontmost app.

### State Machine (`State/AppState.swift`)
All UI and logic flows through `AppState.phase`:
```
idle → recording → transcribing → (cleaning?) → success(preview) → idle
                                              ↘ error(message) → idle
```
`AppState` is the primary `@Observable` singleton. All stores (`Preferences`, `HistoryStore`, `SnippetsStore`, etc.) are also singletons using `@MainActor ObservableObject` with JSON persistence in `~/Library/Application Support/ListenToMe/`.

### Core Pipeline (`Core/`)
Each step is a singleton invoked sequentially by `AppDelegate`:

| Component | Role |
|-----------|------|
| `HotkeyMonitor` | CGEvent tap for global push-to-talk (requires Accessibility) |
| `AudioRecorder` | AVAudioEngine → 16 kHz mono WAV, publishes level ~30 Hz |
| `WhisperRunner` | Spawns bundled `whisper-cli` subprocess, parses output |
| `ClaudeClient` | Spawns the `claude` CLI as a subprocess (`claude --print`) for cleanup |
| `CommandRouter` | Intercepts voice commands (`log to:`, `open`, `shell:`) before paste |
| `Paster` | NSPasteboard write + simulated Cmd+V to frontmost app |

### UI Layer (`UI/`)
- `PillWindow` — always-visible borderless `NSPanel` floating at screen top; wraps `PillView` via `NSHostingView`
- `PillView` — SwiftUI, animates idle (48×48 pulse) / recording (176×176 waveform) / success / error / permission states
- `MenuBarController` — `NSStatusBar` icon + dropdown for status and quick settings
- `MainView` — lazy-loaded tabbed window (Home, History, Snippets, Dictionary, Settings)

### Key Data Flow
1. `HotkeyMonitor.onPress` → `AudioRecorder.start()`
2. `HotkeyMonitor.onRelease` → `AudioRecorder.stop()` → `WhisperRunner.transcribe(wav)` → snippet expansion
3. Cleanup decision via `Preferences.cleanupMode` (smart20/50/always) → `ClaudeClient.clean(text)`
4. `CommandRouter.parse(text)` → execute or `Paster.paste(text)` → `HistoryStore.add(record)`

## Key Conventions

- All singletons follow `Foo.shared` pattern; instantiated in `AppDelegate.applicationDidFinishLaunching`.
- Async work uses Swift `async/await`; all state mutations on `@MainActor`.
- Typed error enums (`WhisperError`, `ClaudeError`) carry `.userMessage` for UI display.
- `ClaudeClient` shells out to the `claude` CLI; cleanup silently degrades if the binary isn't on PATH. The client extends `PATH` with `~/.local/bin`, `~/.npm-global/bin`, `/opt/homebrew/bin`, `/usr/local/bin` since macOS GUI apps inherit a stripped PATH from Finder.
- Whisper model lives at `~/Library/Application Support/ListenToMe/models/ggml-base.en.bin`; `WhisperRunner` verifies presence at launch.
- Post-build script in `project.yml` copies `whisper-cli` + dylibs from `ListenToMe/Resources/` into the app bundle and rewrites `rpath` — required for code signing to succeed.
