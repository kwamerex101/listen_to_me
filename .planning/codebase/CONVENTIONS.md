# Coding Conventions

**Analysis Date:** 2026-05-05

## Naming Patterns

**Files:**
- PascalCase with `.swift` extension: `ListenToMeApp.swift`, `AppState.swift`, `WhisperRunner.swift`
- View files: `PillView.swift`, `HomeView.swift`, `SidebarView.swift`
- UI components grouped in `UI/` directory
- Core services in `Core/`
- State/stores in `State/`

**Functions & Methods:**
- camelCase: `transcribe(wav:prompt:)`, `pasteTracked(_:)`, `handlePhaseChange()`
- Async methods use standard naming without suffix: `clean(_:timeout:)`, `isAvailable(timeout:)`
- Private helper functions: `private func sanitize(cleaned:original:)`, `private func process(buffer:target:)`

**Variables & Properties:**
- camelCase throughout: `state`, `levelBuffer`, `priorPasteboardString`, `recordingStartedAt`
- Boolean properties start with `is` or `should`: `isAvailable`, `hotkeyGranted`, `micGranted`
- Callback properties are descriptive: `onStartTap`, `onStopTap`, `onCancelTap`, `onPillTap`, `onLevel`

**Types & Enums:**
- PascalCase: `AppState`, `Phase`, `WhisperError`, `ClaudeError`, `PasteToken`, `Motion`
- Error enums use `Error` suffix: `WhisperError`, `ClaudeError`
- Phase-driven UI states in `enum Phase`: `.idle`, `.recording`, `.transcribing`, `.polishing`, `.success`, `.error`
- Associated values in enums for rich error context: `case modelNotFound(path: String)`, `case error(message: String)`

## Code Style

**Formatting:**
- No explicit formatter configured (Xcode defaults)
- 4-space indentation
- Compact brace style: `{` on same line

**Access Control:**
- `private` for implementation details within files
- `@MainActor` on classes that must run on the main thread: `AppDelegate`, `AppState`, `AudioRecorder`
- `final` on classes to prevent inheritance: `final class AppDelegate`, `final class AppState`, `final class AudioRecorder`
- Singletons use `static let shared` pattern

## Import Organization

**Order:**
1. SwiftUI imports first: `import SwiftUI`
2. Platform imports: `import AppKit`, `import AVFoundation`, `import Foundation`
3. No unused imports

**Example from `ListenToMeApp.swift`:**
```swift
import SwiftUI
import AppKit
```

**Example from `WhisperRunner.swift`:**
```swift
import Foundation
```

## Error Handling

**Typed Error Enums:**
All error-throwing operations use specific error enums, never generic `NSError` except for user-facing messages.

Examples:

- **WhisperError** (`Core/WhisperRunner.swift`):
  ```swift
  enum WhisperError: Error {
      case binaryNotFound
      case modelNotFound(path: String)
      case processFailed(code: Int32, stderr: String)
      case noOutput
  }
  ```

- **ClaudeError** (`Core/ClaudeClient.swift`):
  ```swift
  enum ClaudeError: Error {
      case binaryNotFound
      case processFailed(code: Int32, stderr: String)
      case timedOut
      case emptyOutput
  }
  ```

- **Error Thrown by Validation Gates**: `PasteToken` validation prevents silently invalid operations
  - Token's `changeCountAtPaste` detects pasteboard mutations
  - Token's `timestamp` allows `maxStaleness` cutoff (default 30 seconds)
  - `Paster.replace(with:token:maxStaleness:)` returns `nil` on validation failure, caller handles fallback

**Try-Catch Pattern:**
Use explicit catches for expected errors, generic catch for logging:
```swift
do {
    let raw = try await WhisperRunner.shared.transcribe(wav: wav, prompt: whisperPrompt)
    // ... happy path
} catch WhisperError.modelNotFound(let path) {
    // Specific handling
    NSLog("[ListenToMe] model not found: \(path)")
    state.phase = .error(message: "Model missing")
} catch {
    // Fallback for unexpected errors
    NSLog("[ListenToMe] transcription failed: \(error)")
    state.phase = .error(message: "Transcribe failed")
}
```

**Process Termination Handling:**
Guard against continuation resumption race (timeout vs. actual termination):
```swift
// From ClaudeClient.runEnv
let didResume = Atomic(false)
let timeoutItem = DispatchWorkItem { ... }
proc.terminationHandler = { p in
    guard didResume.compareAndSet(expected: false, new: true) else { return }
    // Resume continuation only once
}
```

## Logging

**Framework:** Standard `NSLog` + descriptive prefix

**Pattern:**
```swift
NSLog("[ListenToMe] model not found: \(path)")
NSLog("[ListenToMe] cleanup failed, raw stands: \(error)")
NSLog("[ListenToMe] command failed: \(error)")
```

**When to Log:**
- Errors that fall back to safe states (raw transcripts stay in place on cleanup failure)
- Command execution failures
- Model/binary availability issues

## Comments

**When to Comment:**
- Algorithm complexity (e.g., `scopeStartIndex(in:beforeMatch:)` in `VoiceEditor.swift` has detailed explanation of sentence boundary detection)
- Non-obvious state transitions (e.g., AppDelegate comments explain streaming-preview cleanup task and why it's cancelled on new dictation)
- Tricky regex patterns and their purpose

**Code Comments Observed:**
```swift
// One-shot guard so we don't resume the continuation twice
// (e.g. process exits exactly as the timeout fires).
let didResume = Atomic(false)

// Strict cleanup prompt — minimal intervention, reject anything that looks
// like preamble/commentary, match voice exactly.
static let cleanupSystemPrompt: String = ...

/// Captures the state needed to safely replace a paste later
struct PasteToken { ... }
```

**Doc Comments (Brief):**
Use triple-slash comments for public APIs:
```swift
/// Paste-and-track. Returns a token that can be passed to `replace(...)`.
static func pasteTracked(_ text: String) -> PasteToken
```

## Async/Await

**Pattern:** Standard structured concurrency

**Subprocess I/O:**
Use `withCheckedThrowingContinuation` to bridge `Process` callbacks to async:
```swift
func transcribe(wav: URL, prompt: String?) async throws -> String {
    return try await withCheckedThrowingContinuation { cont in
        let proc = Process()
        // ... configure process ...
        proc.terminationHandler = { p in
            // Resume continuation with success or error
            cont.resume(returning: result)
            // or cont.resume(throwing: error)
        }
        try proc.run()
    }
}
```

**Task Cancellation:**
Always check for cancellation in background tasks:
```swift
cleanupTask = Task { [weak self] in
    do {
        let cleaned = try await ClaudeClient.shared.clean(expanded)
        try Task.checkCancellation()  // ← Check before continuing
        await MainActor.run { ... }
    } catch is CancellationError {
        // Handle gracefully
    }
}
```

**Weak Self Pattern:**
Prevent retain cycles in task closures:
```swift
Task { @MainActor [weak self] in
    guard let self else { return }
    // ... use self safely
}
```

## Phase-Driven UI

**AppState.phase** is the single source of truth for UI state:
```swift
enum Phase: Equatable {
    case idle
    case recording
    case transcribing
    case polishing(rawPreview: String)
    case success(preview: String)
    case error(message: String)
    case correcting
}
```

**View Switch Pattern:**
Views examine `state.phase` directly via switch statements (exhaustive):
```swift
switch state.phase {
case .idle:
    // Render idle state
case .recording:
    // Render recording controls
case .success, .polishing:
    // Both states show a pill
default:
    // Other phases
}
```

**onChange Monitoring:**
Views observe phase changes to trigger animations and handlers:
```swift
.onChange(of: phaseID) { _, _ in
    handlePhaseChange()
}
```

## Animation Conventions

**Motion Enum in PillView:**
All spring/curve constants live in a private `Motion` enum (`UI/PillView.swift`, lines 4-23):
```swift
private enum Motion {
    static let phaseSize  = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let phaseSwap  = Animation.spring(response: 0.40, dampingFraction: 0.72)
    static let pressUp    = Animation.spring(response: 0.18, dampingFraction: 0.55)
    static let halo       = Animation.easeOut(duration: 0.45)
    static let shake      = Animation.easeInOut(duration: 0.45)
    static let idleBreath = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    // ...
}
```

**Usage:**
```swift
withAnimation(Motion.pressUp) { pressPop = 1.06 }
.animation(Motion.phaseSize, value: pillWidth)
```

**Custom GeometryEffect:**
Shake animation implemented as `struct Shake: GeometryEffect` with `animatableData` for composability.

## SwiftUI/AppKit Hybrid

**@ObservedObject:**
Views observe `@Published` properties from `ObservableObject` stores:
```swift
@ObservedObject private var state = AppState.shared
@ObservedObject private var history = HistoryStore.shared
```

**@NSApplicationDelegateAdaptor:**
App struct adopts AppKit delegate pattern:
```swift
@main
struct ListenToMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
}
```

**Callback Injection:**
State stores expose optional callbacks that AppDelegate sets:
```swift
state.onStartTap = { [weak self] in self?.handlePress() }
state.onStopTap = { [weak self] in self?.handleRelease() }
```

## Subprocess Pattern

**Consistent across three services:** `WhisperRunner`, `ClaudeClient`, `CommandRouter`

Standard flow:
1. Create `Process` instance
2. Set `executableURL` and `arguments`
3. Pipe stdout/stderr with `Pipe()`
4. Set `terminationHandler` to bridge to async continuation
5. `try proc.run()` wrapped in `withCheckedThrowingContinuation`
6. Capture output in handler, parse, and resume continuation

Example from `WhisperRunner.transcribe`:
```swift
return try await withCheckedThrowingContinuation { cont in
    let proc = Process()
    proc.executableURL = bin
    proc.arguments = args
    let errPipe = Pipe()
    proc.standardError = errPipe
    
    proc.terminationHandler = { p in
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if p.terminationStatus != 0 {
            cont.resume(throwing: WhisperError.processFailed(...))
        } else {
            cont.resume(returning: result)
        }
    }
    try proc.run()
}
```

## Validation Patterns

**PasteToken Validation Gates:**
When replacing text in the target app, `Paster.replace` validates:
1. Pasteboard `changeCount` hasn't shifted (indicates user/clipboard activity)
2. Token age is within `maxStaleness` (default 30s)
3. Focus app still matches original target

Returns `nil` on any validation failure; caller keeps raw text.

**Defensive Model Output Sanitization:**
`ClaudeClient.sanitize` rejects common LLM failure modes:
```swift
// Strip wrapping quotes
// Strip markdown code fences
// Reject known preambles ("here is", "sure,", etc.)
// Reject if word count explodes (>1.4× original)
// Reject if empty
// Otherwise return cleaned text
```

## Singleton Pattern

All shared state and services use `static let shared`:
```swift
class AppState: ObservableObject {
    static let shared = AppState()
    private init() {}  // Prevent accidental creation
}

struct WhisperRunner {
    static let shared = WhisperRunner()
}
```

## File Structure

- **Entry Point:** `ListenToMeApp.swift` — app delegate, lifecycle
- **State:** `State/AppState.swift` — `@Published` properties and callbacks
- **Core Services:** `Core/*` — subprocess runners, state machines, business logic
- **UI Layer:** `UI/*` — SwiftUI views and controllers
- **Resources:** `Resources/` — bundled binaries (whisper-cli) and dylibs

---

*Convention analysis: 2026-05-05*
