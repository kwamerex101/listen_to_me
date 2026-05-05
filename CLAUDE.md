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

<!-- GSD:project-start source:PROJECT.md -->
## Project

**ListenToMe**

A free, local-first macOS menu-bar dictation app for Rex. Press-and-hold a global hotkey, speak, release — Whisper transcribes locally, the `claude` CLI cleans the result up (reusing your existing Claude Code subscription, no separate Anthropic API key), and the polished text pastes into whatever app you're in. Personal tool optimized for daily heavy use; not aimed at distribution.

**Core Value:** **Speak once, ship clean text into any app — fast, offline-by-default, no recurring subscription beyond what you already pay for Claude.** If perceived end-to-end latency, transcript accuracy, or paste fidelity break, nothing else matters.

### Constraints

- **Tech stack**: Swift 5.9, SwiftUI + AppKit, macOS 14.0 (Sonoma) deployment target. No third-party Swift packages — everything is the standard library + Apple frameworks + bundled `whisper.cpp` binaries.
- **Hardware**: Apple Silicon Mac (Metal backend assumed for whisper.cpp performance). Intel macs work but with degraded transcription speed.
- **External dependencies**: `claude` CLI must be on PATH for cleanup (otherwise it silently degrades to raw transcript). Augmented-PATH lookup covers `~/.local/bin`, `~/.npm-global/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
- **Permissions**: Accessibility (CGEventTap for hotkey, Cmd+V simulation for paste), Microphone (AVAudioEngine), Apple Events (paste fidelity).
- **Personal tool ethos**: ad-hoc signing OK, no notarization, hardcoded user-home paths fine, no install ceremony beyond `./scripts/install.sh`.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Swift 5.9 - All application code
## Runtime
- macOS 14.0+ (deployment target, as specified in `project.yml`)
- Xcode project management via XcodeGen
- No Swift Package Manager dependencies declared in this scope
## Frameworks
- SwiftUI - Modern UI framework for settings, correction popover, and pill UI (`ListenToMe/UI/*`)
- AppKit - Menu bar integration, pasteboard control, event simulation (`ListenToMe/Core/MenuBarController.swift`, `ListenToMe/Core/Paster.swift`)
- AVFoundation - Microphone audio capture at 16kHz mono PCM (`ListenToMe/Core/AudioRecorder.swift`)
- CoreGraphics - Keyboard event simulation and hotkey monitoring via CGEvent (`ListenToMe/Core/Paster.swift`, `ListenToMe/Core/HotkeyMonitor.swift`)
- Accessibility API - Global hotkey activation via CGEventTap (requires accessibility permission) (`ListenToMe/Core/HotkeyMonitor.swift`)
- NSWorkspace - Detect frontmost application for targeted paste/replace (`ListenToMe/Core/Paster.swift`)
- XcodeGen - Project generator from `project.yml` specification
## Key Dependencies
- whisper-cli (bundled binary) - Local speech-to-text transcription
- `claude` CLI - External subprocess for transcript cleanup
## Configuration
- Project: `project.yml` (XcodeGen format, defines bundle ID, deployment target, code signing)
- Info.plist: `ListenToMe/Info.plist` and declarative properties in `project.yml`
- Entitlements: `ListenToMe/ListenToMe.entitlements` (microphone audio input permission)
- Post-build script in `project.yml` copies `whisper-cli` and dynamic libraries into the bundle
- Hardened runtime enabled (`ENABLE_HARDENED_RUNTIME: YES`)
- Code signing: Automatic (modern approach, no explicit identity)
- Swift version lock: 5.9 (`SWIFT_VERSION: "5.9"`)
## Platform Requirements
- macOS 14.0 or later
- Xcode (uses Swift 5.9)
- Microphone access (runtime permission)
- Accessibility permission for global hotkey (Fn+Cmd)
- Target: native macOS application (menu-bar accessory app, `LSUIElement: true`)
- Deployment target: macOS 14.0
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- PascalCase with `.swift` extension: `ListenToMeApp.swift`, `AppState.swift`, `WhisperRunner.swift`
- View files: `PillView.swift`, `HomeView.swift`, `SidebarView.swift`
- UI components grouped in `UI/` directory
- Core services in `Core/`
- State/stores in `State/`
- camelCase: `transcribe(wav:prompt:)`, `pasteTracked(_:)`, `handlePhaseChange()`
- Async methods use standard naming without suffix: `clean(_:timeout:)`, `isAvailable(timeout:)`
- Private helper functions: `private func sanitize(cleaned:original:)`, `private func process(buffer:target:)`
- camelCase throughout: `state`, `levelBuffer`, `priorPasteboardString`, `recordingStartedAt`
- Boolean properties start with `is` or `should`: `isAvailable`, `hotkeyGranted`, `micGranted`
- Callback properties are descriptive: `onStartTap`, `onStopTap`, `onCancelTap`, `onPillTap`, `onLevel`
- PascalCase: `AppState`, `Phase`, `WhisperError`, `ClaudeError`, `PasteToken`, `Motion`
- Error enums use `Error` suffix: `WhisperError`, `ClaudeError`
- Phase-driven UI states in `enum Phase`: `.idle`, `.recording`, `.transcribing`, `.polishing`, `.success`, `.error`
- Associated values in enums for rich error context: `case modelNotFound(path: String)`, `case error(message: String)`
## Code Style
- No explicit formatter configured (Xcode defaults)
- 4-space indentation
- Compact brace style: `{` on same line
- `private` for implementation details within files
- `@MainActor` on classes that must run on the main thread: `AppDelegate`, `AppState`, `AudioRecorder`
- `final` on classes to prevent inheritance: `final class AppDelegate`, `final class AppState`, `final class AudioRecorder`
- Singletons use `static let shared` pattern
## Import Organization
## Error Handling
- **WhisperError** (`Core/WhisperRunner.swift`):
- **ClaudeError** (`Core/ClaudeClient.swift`):
- **Error Thrown by Validation Gates**: `PasteToken` validation prevents silently invalid operations
## Logging
- Errors that fall back to safe states (raw transcripts stay in place on cleanup failure)
- Command execution failures
- Model/binary availability issues
## Comments
- Algorithm complexity (e.g., `scopeStartIndex(in:beforeMatch:)` in `VoiceEditor.swift` has detailed explanation of sentence boundary detection)
- Non-obvious state transitions (e.g., AppDelegate comments explain streaming-preview cleanup task and why it's cancelled on new dictation)
- Tricky regex patterns and their purpose
## Async/Await
## Phase-Driven UI
## Animation Conventions
## SwiftUI/AppKit Hybrid
## Subprocess Pattern
## Validation Patterns
## Singleton Pattern
## File Structure
- **Entry Point:** `ListenToMeApp.swift` — app delegate, lifecycle
- **State:** `State/AppState.swift` — `@Published` properties and callbacks
- **Core Services:** `Core/*` — subprocess runners, state machines, business logic
- **UI Layer:** `UI/*` — SwiftUI views and controllers
- **Resources:** `Resources/` — bundled binaries (whisper-cli) and dylibs
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | File |
|-----------|----------------|------|
| AppDelegate | Orchestrates hotkey press/release, phase transitions, cleanup task lifecycle | `ListenToMe/ListenToMeApp.swift` |
| AppState | Observable phase state machine (idle → recording → transcribing → polishing → success → idle, plus error/correcting) | `ListenToMe/State/AppState.swift` |
| HotkeyMonitor | Global Fn+Cmd modifier tap; auto-retries if Accessibility denied | `ListenToMe/Core/HotkeyMonitor.swift` |
| AudioRecorder | Records mic to WAV at 16kHz mono; publishes RMS level ~30Hz | `ListenToMe/Core/AudioRecorder.swift` |
| WhisperRunner | Spawns whisper-cli subprocess; feeds WAV, reads .txt output | `ListenToMe/Core/WhisperRunner.swift` |
| CommandRouter | Parses voice commands (log today, open app, shell); executes synchronously | `ListenToMe/Core/CommandRouter.swift` |
| VoiceEditor | Pure transforms: punctuation, scratch-that undo, new paragraph/line | `ListenToMe/Core/VoiceEditor.swift` |
| SnippetsStore | Keyword↔expansion pairs; applies in order of word count (longest first) | `ListenToMe/State/SnippetsStore.swift` |
| Paster | Posts text to pasteboard, simulates Cmd+V, enables Cmd+Z+Cmd+V replace with validation | `ListenToMe/Core/Paster.swift` |
| ClaudeClient | Spawns claude CLI subprocess; applies system prompt for cleanup | `ListenToMe/Core/ClaudeClient.swift` |
| PillWindow | Always-visible NSPanel (click-through by default); hosts PillView | `ListenToMe/UI/PillWindow.swift` |
| CorrectionWindow | Transient NSPanel (becomes key); hosts TextField for inline editing | `ListenToMe/UI/CorrectionWindow.swift` |
| HistoryStore | Persists transcript records (raw + final text, duration, word count) | `ListenToMe/State/HistoryStore.swift` |
| Preferences | Stores hotkey binding, cleanup mode, other settings | `ListenToMe/State/Preferences.swift` |
## Pattern Overview
- **State machine drives UI**: Phase enum (idle, recording, transcribing, polishing, success, error, correcting) is the single source of truth
- **Streaming preview**: Raw text pastes immediately, cleanup runs in background with three validation gates before replace
- **Singleton services**: Each major subsystem (AudioRecorder, WhisperRunner, ClaudeClient, Paster) is a shared instance
- **Process-based CLI**: Whisper and Claude are launched as subprocesses (Process + Pipe + terminationHandler), not linked libraries
- **MainActor enforcement**: All UI-touching code runs on main thread; async work checks cancellation and marshals back via MainActor.run
## Layers
- Purpose: Capture audio and monitor global hotkey
- Location: `ListenToMe/Core/HotkeyMonitor.swift`, `ListenToMe/Core/AudioRecorder.swift`
- Contains: AVAudioEngine taps, CGEventTap callbacks
- Depends on: AppKit, AVFoundation, CoreGraphics
- Used by: AppDelegate (via onPress/onRelease callbacks and start/stop methods)
- Purpose: Convert WAV to text via whisper.cpp binary
- Location: `ListenToMe/Core/WhisperRunner.swift`
- Contains: Process spawning, WAV file handling, model path resolution
- Depends on: whisper-cli binary + ggml-base.en.bin model (bundled)
- Used by: AppDelegate (called after stop() to generate raw transcript)
- Purpose: Apply deterministic edits (punctuation, scratch-that, snippets) before cleanup
- Locations: `ListenToMe/Core/VoiceEditor.swift`, `ListenToMe/Core/CommandRouter.swift`, `ListenToMe/State/SnippetsStore.swift`
- Contains: Regex-based text transforms (pure functions), voice command parsing, snippet expansion
- Depends on: Foundation (NSRegularExpression)
- Used by: AppDelegate pipeline (VoiceEditor → CommandRouter → SnippetsStore)
- Purpose: Polish transcript asynchronously via Claude
- Location: `ListenToMe/Core/ClaudeClient.swift`
- Contains: claude CLI subprocess, system prompt for strict cleanup, timeout handling
- Depends on: claude binary (via /usr/bin/env), ANTHROPIC_API_KEY or OAuth keychain
- Used by: AppDelegate.startCleanupTask() as a background Task
- Purpose: Write to pasteboard, simulate keystrokes, safely swap pasted text later
- Location: `ListenToMe/Core/Paster.swift`
- Contains: Pasteboard manipulation, Cmd+V/Cmd+Z simulation, PasteToken tracking, three validation gates
- Depends on: AppKit (NSPasteboard, NSWorkspace, CGEvent)
- Used by: AppDelegate (pasteTracked, replace, finalize)
- Purpose: Store observable app state, user settings, history, snippets
- Locations: `ListenToMe/State/AppState.swift`, `ListenToMe/State/Preferences.swift`, `ListenToMe/State/HistoryStore.swift`, `ListenToMe/State/SnippetsStore.swift`, `ListenToMe/State/DictionaryStore.swift`, `ListenToMe/State/StyleStore.swift`, `ListenToMe/State/TransformsStore.swift`, `ListenToMe/State/PagesStore.swift`, `ListenToMe/State/ScratchpadStore.swift`
- Contains: @MainActor ObservableObject classes, JSON persistence to ~/Library/Application Support/ListenToMe/
- Depends on: Combine, Foundation
- Used by: AppDelegate (updates), SwiftUI views (observe via @ObservedObject)
- Purpose: Render state as SwiftUI views and AppKit windows
- Locations: `ListenToMe/UI/PillView.swift`, `ListenToMe/UI/PillWindow.swift`, `ListenToMe/UI/CorrectionWindow.swift`, `ListenToMe/UI/MainView.swift`, `ListenToMe/UI/MenuBarController.swift`, `ListenToMe/UI/WaveformView.swift` (and settings UI)
- Contains: SwiftUI animatable properties, AppKit panel lifecycle, gesture handling
- Depends on: SwiftUI, AppKit, AVFoundation (for waveform)
- Used by: AppDelegate (installs windows, wires callbacks), end user
- Purpose: Sounds, haptics, launch-at-login, menu-bar status
- Locations: `ListenToMe/Core/SoundCue.swift`, `ListenToMe/Core/Haptics.swift`, `ListenToMe/Core/LaunchAtLogin.swift`, `ListenToMe/UI/MenuBarController.swift`
- Contains: AVAudioPlayer, NSHapticFeedback, NSStatusBar
- Depends on: AppKit, AVFoundation
- Used by: AppDelegate (feedback on state changes)
## Data Flow
### Primary Request Path (Happy Path)
### Inline Correction Flow
- AppState.shared is singleton, @MainActor, @Published
- Phase enum drives UI shape, button availability, pill animation
- lastTranscript cached for correction context
- lastPasteToken tracks most-recent paste for validation gates
- All updates marshaled through AppDelegate on main thread
- HistoryStore persists all transcripts; Preferences saves user settings
## Key Abstractions
- Purpose: Single source of truth for app mode (idle, recording, transcribing, polishing, success, error, correcting)
- Examples: `ListenToMe/State/AppState.swift:4–19`
- Pattern: enum associated values (Phase.error(message: String), Phase.polishing(rawPreview: String), Phase.success(preview: String))
- Purpose: Opaque reference to a paste event; enables safe replace later
- Examples: `ListenToMe/Core/Paster.swift:5–17`
- Pattern: Struct capturing pasteboard changeCount, bundleId, timestamp for three validation gates
- Purpose: Global shared instances with no public initializers
- Examples: AppState.shared, AudioRecorder.shared, HotkeyMonitor.shared, WhisperRunner.shared, ClaudeClient.shared, SnippetsStore.shared, HistoryStore.shared
- Pattern: @MainActor final class / struct with static let shared = Type()
- Purpose: AppKit windows with custom lifecycle (click-through, always-on-top, stationary)
- PillWindow: nonactivatingPanel, ignoresMouseEvents=true by default (set interactive when recording)
- CorrectionWindow: nonactivatingPanel, canBecomeKey=true, focus for TextField
- Pattern: Subclass NSPanel, set level=.floating, collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary], host SwiftUI via NSHostingView
## Entry Points
- Location: `ListenToMe/ListenToMeApp.swift:4–14` (@main struct)
- Triggers: macOS app delegate lifecycle
- Responsibilities: Defines empty scene (menu-bar app), installs AppDelegate
- Location: `ListenToMe/ListenToMeApp.swift:31–88`
- Triggers: OS after app is fully initialized
- Responsibilities: Set accessory policy (hide from Dock), install menu bar & pill, request mic permission, probe claude CLI availability, wire hotkey & button callbacks, start phase-change notification loop
- Location: HotkeyMonitor callbacks → AppDelegate.handlePress/Release (`ListenToMe/ListenToMeApp.swift:92–237`)
- Triggers: User holds Fn+Cmd (or other configured combo)
- Responsibilities: Start/stop recording, initiate transcription pipeline, manage cleanup task lifecycle
- Location: AppDelegate.handlePillTap (`ListenToMe/ListenToMeApp.swift:302–322`)
- Triggers: User clicks pill during .success or .polishing phase
- Responsibilities: Open CorrectionWindow, enable inline editing
## Architectural Constraints
- **Threading:** Main thread only (all UI, all state updates marked @MainActor); background work (ClaudeClient.clean) runs in detached Tasks, checks cancellation, marshals results back via MainActor.run
- **Global state:** AppState.shared is a singleton; AudioRecorder.shared, HotkeyMonitor.shared, WhisperRunner.shared, ClaudeClient.shared, Paster (enum), SnippetsStore.shared, HistoryStore.shared all singletons. Paster is stateless (token-based), others are @MainActor
- **Circular imports:** None detected; clear dependency graph (UI → State → Core → Foundation/AppKit)
- **Process spawning:** No linked dylibs for Whisper or Claude; both launched as subprocesses via NSTask/Process. whisper-cli and dylibs bundled in app (copied by build script); claude resolved via /usr/bin/env (uses PATH)
- **Pasteboard mutations:** Three-gate validation in replace() to ensure safe text swaps (staleness, bundle ID match, changeCount unchanged)
- **Model file:** whisper model lives at ~/Library/Application Support/ListenToMe/models/ggml-base.en.bin (user-downloaded or from setup script)
- **Microphone access:** Requested at launch; controls whether recording is allowed; shown in permission card if denied
- **Accessibility access:** Hotkey monitor requires AXIsProcessTrusted(); if not granted, retries every 2s until success (no app relaunch needed)
## Anti-Patterns
### Blocking on Cleanup
### Destroying PasteToken on Validation Failure
### Paste Without Token Tracking
## Error Handling
- **Mic permission missing:** `.error("Mic permission needed")` at handlePress; user sees permission card
- **Recording failed:** `.error("Record failed")` at start() throw; rare (file I/O error)
- **Empty transcript:** `.error("Empty transcript")` if whisper returns ""; user spoke too quietly
- **Transcription failed:** `.error("Transcribe failed")` if whisper process exits nonzero; logs stderr to Console
- **Cleanup failed:** Raw text stands; logged to Console; HistoryStore records raw (not polished)
- **Replace validation gates:** Silently abort (raw stays); user unaware (by design; gates handle edge cases transparently)
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
