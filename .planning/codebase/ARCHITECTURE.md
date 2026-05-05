<!-- refreshed: 2026-05-05 -->
# Architecture

**Analysis Date:** 2026-05-05

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                          Hotkey & Recording Layer                         │
│       HotkeyMonitor (Fn+Cmd global tap)  ←→  AudioRecorder (AVAudio)    │
└──────────────────────┬───────────────────────────────────────────────────┘
                       │ onPress/onRelease
                       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       AppDelegate (Event Orchestration)                   │
│    Phase state machine, callback wiring, cleanup task management         │
│                  `ListenToMe/ListenToMeApp.swift`                        │
└───┬──────┬──────┬──────┬──────────────────────────────────────────────────┘
    │      │      │      │
    ▼      ▼      ▼      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          Post-Release Pipeline                             │
│                                                                             │
│  WhisperRunner (transcribe)  ↓                                             │
│        ↓                                                                     │
│  CommandRouter.parse (voice commands: log today/open app/shell) ↓         │
│        ↓                                                                     │
│  VoiceEditor.apply (punctuation, scratch that, new paragraph) ↓           │
│        ↓                                                                     │
│  SnippetsStore.expand (keyword → expansion) ↓                             │
│        ↓                                                                     │
│  Paster.pasteTracked (raw paste immediately, return token) ↓              │
│        ↓                                                                     │
│  [Background] ClaudeClient.clean (polish & fix, async) ↓                 │
│        ↓                                                                     │
│  Paster.replace (if gates pass: staleness, bundle ID, changeCount) ↓     │
│        ↓                                                                     │
│  [No-cleanup mode] Paster.finalize (restore prior clipboard)              │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
                       │ Streaming preview
                       ▼
         ┌─────────────────────────────┐
         │  Raw text in target app      │
         │  User sees result in ~1.5s   │
         └─────────────────────────────┘
                       │ (User can click pill to open correction)
                       ▼
         ┌─────────────────────────────┐
         │  CorrectionWindow opens      │
         │  TextField gains focus       │
         │  Cmd+Z+Cmd+V replaces       │
         │  (unless validation fails)   │
         └─────────────────────────────┘
                       │
                       ▼
         ┌─────────────────────────────┐
         │  HistoryStore.add           │
         │  (final text recorded)      │
         └─────────────────────────────┘
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

**Overall:** Reactive state machine (AppState) with singleton services (AudioRecorder, HotkeyMonitor, ClaudeClient, Paster) orchestrated by AppDelegate. SwiftUI observes AppState; two AppKit NSPanel windows for pill (always-visible) and correction (transient, keyboard-enabled).

**Key Characteristics:**
- **State machine drives UI**: Phase enum (idle, recording, transcribing, polishing, success, error, correcting) is the single source of truth
- **Streaming preview**: Raw text pastes immediately, cleanup runs in background with three validation gates before replace
- **Singleton services**: Each major subsystem (AudioRecorder, WhisperRunner, ClaudeClient, Paster) is a shared instance
- **Process-based CLI**: Whisper and Claude are launched as subprocesses (Process + Pipe + terminationHandler), not linked libraries
- **MainActor enforcement**: All UI-touching code runs on main thread; async work checks cancellation and marshals back via MainActor.run

## Layers

**Recording Layer:**
- Purpose: Capture audio and monitor global hotkey
- Location: `ListenToMe/Core/HotkeyMonitor.swift`, `ListenToMe/Core/AudioRecorder.swift`
- Contains: AVAudioEngine taps, CGEventTap callbacks
- Depends on: AppKit, AVFoundation, CoreGraphics
- Used by: AppDelegate (via onPress/onRelease callbacks and start/stop methods)

**Transcription Layer:**
- Purpose: Convert WAV to text via whisper.cpp binary
- Location: `ListenToMe/Core/WhisperRunner.swift`
- Contains: Process spawning, WAV file handling, model path resolution
- Depends on: whisper-cli binary + ggml-base.en.bin model (bundled)
- Used by: AppDelegate (called after stop() to generate raw transcript)

**Transformation Layer:**
- Purpose: Apply deterministic edits (punctuation, scratch-that, snippets) before cleanup
- Locations: `ListenToMe/Core/VoiceEditor.swift`, `ListenToMe/Core/CommandRouter.swift`, `ListenToMe/State/SnippetsStore.swift`
- Contains: Regex-based text transforms (pure functions), voice command parsing, snippet expansion
- Depends on: Foundation (NSRegularExpression)
- Used by: AppDelegate pipeline (VoiceEditor → CommandRouter → SnippetsStore)

**Cleanup Layer (Background):**
- Purpose: Polish transcript asynchronously via Claude
- Location: `ListenToMe/Core/ClaudeClient.swift`
- Contains: claude CLI subprocess, system prompt for strict cleanup, timeout handling
- Depends on: claude binary (via /usr/bin/env), ANTHROPIC_API_KEY or OAuth keychain
- Used by: AppDelegate.startCleanupTask() as a background Task

**Paste & Replace Layer:**
- Purpose: Write to pasteboard, simulate keystrokes, safely swap pasted text later
- Location: `ListenToMe/Core/Paster.swift`
- Contains: Pasteboard manipulation, Cmd+V/Cmd+Z simulation, PasteToken tracking, three validation gates
- Depends on: AppKit (NSPasteboard, NSWorkspace, CGEvent)
- Used by: AppDelegate (pasteTracked, replace, finalize)

**State & Persistence Layer:**
- Purpose: Store observable app state, user settings, history, snippets
- Locations: `ListenToMe/State/AppState.swift`, `ListenToMe/State/Preferences.swift`, `ListenToMe/State/HistoryStore.swift`, `ListenToMe/State/SnippetsStore.swift`, `ListenToMe/State/DictionaryStore.swift`, `ListenToMe/State/StyleStore.swift`, `ListenToMe/State/TransformsStore.swift`, `ListenToMe/State/PagesStore.swift`, `ListenToMe/State/ScratchpadStore.swift`
- Contains: @MainActor ObservableObject classes, JSON persistence to ~/Library/Application Support/ListenToMe/
- Depends on: Combine, Foundation
- Used by: AppDelegate (updates), SwiftUI views (observe via @ObservedObject)

**UI Layer:**
- Purpose: Render state as SwiftUI views and AppKit windows
- Locations: `ListenToMe/UI/PillView.swift`, `ListenToMe/UI/PillWindow.swift`, `ListenToMe/UI/CorrectionWindow.swift`, `ListenToMe/UI/MainView.swift`, `ListenToMe/UI/MenuBarController.swift`, `ListenToMe/UI/WaveformView.swift` (and settings UI)
- Contains: SwiftUI animatable properties, AppKit panel lifecycle, gesture handling
- Depends on: SwiftUI, AppKit, AVFoundation (for waveform)
- Used by: AppDelegate (installs windows, wires callbacks), end user

**Utility Layer:**
- Purpose: Sounds, haptics, launch-at-login, menu-bar status
- Locations: `ListenToMe/Core/SoundCue.swift`, `ListenToMe/Core/Haptics.swift`, `ListenToMe/Core/LaunchAtLogin.swift`, `ListenToMe/UI/MenuBarController.swift`
- Contains: AVAudioPlayer, NSHapticFeedback, NSStatusBar
- Depends on: AppKit, AVFoundation
- Used by: AppDelegate (feedback on state changes)

## Data Flow

### Primary Request Path (Happy Path)

1. **Hotkey press** — HotkeyMonitor.onPress fires (`ListenToMe/ListenToMeApp.swift:66`)
   - AppDelegate.handlePress() called
   - Validates mic permission, cancels any in-flight cleanup
   - AudioRecorder.start() → records to temp WAV
   - state.phase = .recording
   - Haptics/sound feedback

2. **Hotkey release** — HotkeyMonitor.onRelease fires
   - AppDelegate.handleRelease() called
   - AudioRecorder.stop() returns URL
   - state.phase = .transcribing

3. **Transcribe** — WhisperRunner.transcribe(wav:) async
   - Spawns whisper-cli subprocess
   - Reads .txt output, deletes temp files
   - Returns raw transcript string

4. **Parse voice commands** — CommandRouter.parse(raw)
   - Pattern matches "log today:", "open", "shell:"
   - If match → execute (log file, launch app, run shell) and return summary
   - Recorded in history; early exit, no paste/cleanup

5. **Transform** — VoiceEditor.apply(raw)
   - Phase 1: punctuation substitution (question mark → ?)
   - Phase 2: scratch-that deletion (remove prior sentence)
   - Phase 3: new paragraph/line breaks
   - Phase 4: tidy whitespace

6. **Expand snippets** — SnippetsStore.expand(edited)
   - For each snippet (longest first): case-insensitive word-boundary replace

7. **Paste immediately** (streaming preview) — Paster.pasteTracked(expanded)
   - Clear pasteboard, write expanded text, capture changeCount
   - Simulate Cmd+V into frontmost app
   - Return PasteToken (bundleId, changeCountAtPaste, timestamp, prior clipboard)
   - state.phase = .polishing
   - Haptics/sound feedback
   - **User sees text in ~1.5s**

8. **Background cleanup** (conditional) — AppDelegate.startCleanupTask()
   - If cleanupMode.shouldClean(wordCount): spawn ClaudeClient.clean()
   - Pass text through claude CLI with strict cleanup prompt
   - No preamble, fix punctuation/capitalization, remove fillers
   - On success, call Paster.replace(newText, token)

9. **Replace validation** — Paster.replace(with:token:maxStaleness:)
   - **Gate 1: Staleness** — if > 30s, abort (finalize, return nil)
   - **Gate 2: Bundle ID** — if frontmost app ≠ token.bundleId, abort
   - **Gate 3: Pasteboard changeCount** — if user touched clipboard, abort
   - If all pass: simulate Cmd+Z, wait 80ms, write new text, simulate Cmd+V
   - Return fresh PasteToken; caller updates lastPasteToken

10. **History** — HistoryStore.add(raw, final, duration)
    - Records raw → final transcript pair for later review

11. **Auto-reset** — autoReset(after: 3.0) called
    - state.phase = .idle after delay
    - PillWindow becomes click-through again

### Inline Correction Flow

1. **User clicks pill during .success/.polishing** — AppDelegate.handlePillTap()
   - Validates lastPasteToken is still valid
   - Cancels any in-flight cleanup
   - state.phase = .correcting
   - CorrectionWindow.show(initialText: token.pastedText)

2. **CorrectionWindow opens** (`ListenToMe/UI/CorrectionWindow.swift:37–63`)
   - Becomes key (NSPanel.canBecomeKey = true)
   - Positions above pill
   - NSHostingView renders CorrectionView with TextField
   - App is activated so keyboard focus works

3. **User edits & presses Enter** — CorrectionView.onApply fires
   - CorrectionWindow dismisses
   - Re-activates original target app (by bundleId)
   - **Calls Paster.replace(corrected, token)** with same validation gates
   - On success, updates lastPasteToken and HistoryStore
   - state.phase = .success

**State Management:**
- AppState.shared is singleton, @MainActor, @Published
- Phase enum drives UI shape, button availability, pill animation
- lastTranscript cached for correction context
- lastPasteToken tracks most-recent paste for validation gates
- All updates marshaled through AppDelegate on main thread
- HistoryStore persists all transcripts; Preferences saves user settings

## Key Abstractions

**Phase State Machine:**
- Purpose: Single source of truth for app mode (idle, recording, transcribing, polishing, success, error, correcting)
- Examples: `ListenToMe/State/AppState.swift:4–19`
- Pattern: enum associated values (Phase.error(message: String), Phase.polishing(rawPreview: String), Phase.success(preview: String))

**PasteToken:**
- Purpose: Opaque reference to a paste event; enables safe replace later
- Examples: `ListenToMe/Core/Paster.swift:5–17`
- Pattern: Struct capturing pasteboard changeCount, bundleId, timestamp for three validation gates

**Singleton Services:**
- Purpose: Global shared instances with no public initializers
- Examples: AppState.shared, AudioRecorder.shared, HotkeyMonitor.shared, WhisperRunner.shared, ClaudeClient.shared, SnippetsStore.shared, HistoryStore.shared
- Pattern: @MainActor final class / struct with static let shared = Type()

**NSPanel Windows:**
- Purpose: AppKit windows with custom lifecycle (click-through, always-on-top, stationary)
- PillWindow: nonactivatingPanel, ignoresMouseEvents=true by default (set interactive when recording)
- CorrectionWindow: nonactivatingPanel, canBecomeKey=true, focus for TextField
- Pattern: Subclass NSPanel, set level=.floating, collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary], host SwiftUI via NSHostingView

## Entry Points

**App Launch:**
- Location: `ListenToMe/ListenToMeApp.swift:4–14` (@main struct)
- Triggers: macOS app delegate lifecycle
- Responsibilities: Defines empty scene (menu-bar app), installs AppDelegate

**AppDelegate.applicationDidFinishLaunching:**
- Location: `ListenToMe/ListenToMeApp.swift:31–88`
- Triggers: OS after app is fully initialized
- Responsibilities: Set accessory policy (hide from Dock), install menu bar & pill, request mic permission, probe claude CLI availability, wire hotkey & button callbacks, start phase-change notification loop

**Hotkey Press/Release:**
- Location: HotkeyMonitor callbacks → AppDelegate.handlePress/Release (`ListenToMe/ListenToMeApp.swift:92–237`)
- Triggers: User holds Fn+Cmd (or other configured combo)
- Responsibilities: Start/stop recording, initiate transcription pipeline, manage cleanup task lifecycle

**Pill Click:**
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

**What happens:** If cleanup (ClaudeClient.clean) ran synchronously on the main thread, the UI would freeze until claude CLI finishes (10–20s).

**Why it's wrong:** Unresponsive app; pill can't update phase or dismiss while waiting.

**Do this instead:** Cleanup runs in a detached Task (`ListenToMe/ListenToMeApp.swift:248`). AppDelegate.startCleanupTask() wraps the async work and checks cancellation. Main thread stays free for user input.

### Destroying PasteToken on Validation Failure

**What happens:** If bundle ID doesn't match (user switched apps), a naive approach would silently drop the old text and leave the user's app with wrong data.

**Why it's wrong:** Silent data loss; user has no way to know the polished version was rejected.

**Do this instead:** Paster.replace() validates three gates and returns nil on failure. Raw text stays in place. AppDelegate logs the gate failure and keeps the raw transcript in HistoryStore. User doesn't see a difference.

### Paste Without Token Tracking

**What happens:** If Paster.paste() (one-shot) is used instead of pasteTracked(), the cleanup pipeline can't know which pasteboard entry to replace later.

**Why it's wrong:** Cleanup finishes but has no way to find and swap the right text; multiple dictations blur together on pasteboard.

**Do this instead:** All streaming-preview flow uses pasteTracked() to return PasteToken. Token is passed through the entire cleanup chain. Only finalize() is called if replace() failed.

## Error Handling

**Strategy:** Errors are caught at each pipeline stage and trigger early termination (state.phase = .error(message:)) with auto-reset. Errors are logged to Console.app via NSLog.

**Patterns:**
- **Mic permission missing:** `.error("Mic permission needed")` at handlePress; user sees permission card
- **Recording failed:** `.error("Record failed")` at start() throw; rare (file I/O error)
- **Empty transcript:** `.error("Empty transcript")` if whisper returns ""; user spoke too quietly
- **Transcription failed:** `.error("Transcribe failed")` if whisper process exits nonzero; logs stderr to Console
- **Cleanup failed:** Raw text stands; logged to Console; HistoryStore records raw (not polished)
- **Replace validation gates:** Silently abort (raw stays); user unaware (by design; gates handle edge cases transparently)

## Cross-Cutting Concerns

**Logging:** NSLog used throughout for debugging (visible in Console.app). No unified logger; strings prefixed with "[ListenToMe]".

**Validation:** Handled in Paster.replace() with three gates (staleness, bundle ID, changeCount). Voice editor and command router parse defensively (bail on empty input, regex failures).

**Authentication:** ClaudeClient looks up claude CLI via /usr/bin/env and PATH; no explicit API key in code. claude CLI reads ANTHROPIC_API_KEY or uses OAuth keychain (via Claude Code subscription).

**Accessibility:** HotkeyMonitor.isAccessibilityGranted() checks AXIsProcessTrusted(); if denied, shows permission card and retries every 2s. No user prompt from app; OS provides System Settings link.

---

*Architecture analysis: 2026-05-05*
