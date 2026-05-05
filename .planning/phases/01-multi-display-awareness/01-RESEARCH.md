# Phase 1: Multi-Display Awareness - Research

**Researched:** 2026-05-05
**Domain:** macOS AppKit multi-screen NSPanel positioning
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** "Active screen" = screen containing `NSEvent.mouseLocation` at the moment the pill needs to show. Falls back to `NSScreen.main` only if cursor isn't over any connected screen.
- **D-02:** Do NOT use frontmost-app's main window position.
- **D-03:** Reposition only at two moments: (1) right before transitioning from `.idle` into any visible phase; (2) on `NSApplication.didChangeScreenParametersNotification`.
- **D-04:** No continuous cursor tracking. No mouse-move observer.
- **D-05:** Single `PillWindow` instance. No per-screen mirroring.
- **D-06:** Pill repositions at press → recording phase transition; idle pill stays on last screen until new dictation or monitor change.

### Claude's Discretion
- Exact insertion point for the reposition call (likely `AppDelegate.handlePress()` before `state.phase = .recording`).
- Whether to refactor `PillWindow.positionAtTop()` or add a sibling method (rename is fair game).
- Whether `CorrectionWindow` gets same logic in this phase (if trivial) or deferred.
- Observer lifecycle for `didChangeScreenParametersNotification` — addObserver on `PillWindow.shared` at init or in `applicationDidFinishLaunching`.

### Deferred Ideas (OUT OF SCOPE)
- Continuous cursor tracking
- Pill mirrored across all screens
- `CorrectionWindow` active-screen logic (possibly folded in if trivial, else follow-on)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DISPLAY-01 | When pill becomes visible (recording, transcribing, polishing, success, error, correcting), `PillWindow` repositions to the `NSScreen` containing `NSEvent.mouseLocation` before being shown. Falls back to `NSScreen.main`. | `activeScreen()` helper iterates `NSScreen.screens`, tests `screen.frame.contains(mouseLocation)`, returns first match or `.main`. |
| DISPLAY-02 | `PillWindow` re-anchors on `NSApplication.didChangeScreenParametersNotification` (monitor connect/disconnect/rearrange). | Observer registered once at init; handler calls same reposition method; debounce recommended due to macOS 14 behavior. |
</phase_requirements>

---

## Summary

The change is small in lines but requires careful attention to three API-level gotchas that would produce subtle bugs if ignored: (1) `NSEvent.mouseLocation` coordinate space, (2) `visibleFrame` vs `frame` selection for anchoring, and (3) `didChangeScreenParametersNotification` firing more than once per physical display event on macOS 14+.

`PillWindow.positionAtTop()` already does 90% of what we need — it reads `NSScreen.main` and uses `visibleFrame`. The only surgery is replacing `NSScreen.main` with an `activeScreen()` helper that resolves from `NSEvent.mouseLocation`, and wiring a `NotificationCenter` observer for display config changes.

**Primary recommendation:** Add a private `activeScreen() -> NSScreen` helper, replace the `NSScreen.main` reference in (the renamed) `positionAtTop()`, and register a debounced `didChangeScreenParametersNotification` observer in `PillWindow.init()`. One new method, one renamed method, one observer — no architectural change.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Resolve active screen from cursor | NSPanel (PillWindow) | AppDelegate | PillWindow owns its own geometry; screen resolution is positioning logic |
| Trigger reposition on dictation start | AppDelegate | — | AppDelegate owns phase transitions; calls PillWindow API |
| Trigger reposition on display change | PillWindow (observer) | — | Self-contained; PillWindow re-positions itself without AppDelegate involvement |
| Fallback to NSScreen.main | PillWindow | — | Pure positioning logic inside window class |

---

## Standard Stack

### Core (all already in project)
| API | Source | Purpose |
|-----|--------|---------|
| `NSEvent.mouseLocation` | AppKit | Global cursor position in screen coordinates — class property, no instance needed |
| `NSScreen.screens` | AppKit | Array of all connected displays; iterate to find which contains cursor |
| `NSScreen.visibleFrame` | AppKit | Screen rect minus Dock, menu bar, notch — use for window anchoring |
| `NSScreen.main` | AppKit | Fallback when cursor not over any screen |
| `NSApplication.didChangeScreenParametersNotification` | AppKit | Posted on monitor connect/disconnect/rearrange |
| `NotificationCenter.default` | Foundation | Observer registration — already used in `MenuBarController` for `.phaseChanged` |

No new packages. No new imports beyond what `PillWindow.swift` already has (`import AppKit`).

---

## Architecture Patterns

### System Architecture Diagram

```
User presses hotkey
        |
        v
AppDelegate.handlePress()
        |
        +-- PillWindow.shared.repositionToActiveScreen()
        |           |
        |           +-- NSEvent.mouseLocation  --> NSPoint (screen coords)
        |           +-- NSScreen.screens       --> iterate .frame.contains()
        |           +-- NSScreen.visibleFrame  --> anchor x/y
        |           +-- setFrame(_:display:)   [main thread — already @MainActor]
        |
        +-- state.phase = .recording  (pill becomes visible)

Display config change
        |
        v
NSApplication.didChangeScreenParametersNotification
        |
        v
PillWindow (observer, registered in init)
        |
        +-- debounce 0.1s (coalesce rapid macOS 14 bursts)
        |
        +-- PillWindow.shared.repositionToActiveScreen()
```

### Recommended Project Structure

No new files. All changes in:
```
ListenToMe/UI/PillWindow.swift          # activeScreen() + renamed positionAtTop + observer
ListenToMe/ListenToMeApp.swift          # one-line call in handlePress() before .recording
```

`CorrectionWindow.swift` — fold in same `activeScreen()` call if the change is < 3 lines; otherwise defer.

### Pattern: Active Screen Resolution

```swift
// Source: Apple Developer Documentation — NSEvent.mouseLocation, NSScreen.screens
// [VERIFIED: Apple developer docs + WebSearch cross-reference]

/// Returns the NSScreen that currently contains the cursor,
/// or NSScreen.main as a fallback.
private func activeScreen() -> NSScreen {
    let pt = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens[0]   // belt-and-suspenders: main is nil only in unit tests
}
```

`NSMouseInRect` is the idiomatic AppKit test; equivalent to `frame.contains(pt)` but handles edge-pixel semantics correctly. [ASSUMED: behavioral equivalence — no official doc distinguishes them for this use case; either works in practice]

### Pattern: Repositioning the Window

```swift
// Renamed from positionAtTop() — name was misleading (positions at bottom of visibleFrame)
func repositionToActiveScreen() {
    let screen = activeScreen()
    let visible = screen.visibleFrame
    let s = Self.windowSize
    let x = visible.midX - s.width / 2
    let y = visible.minY + 4    // just above Dock, same constant as before
    setFrame(NSRect(x: x, y: y, width: s.width, height: s.height), display: true)
}
```

**Thread safety:** `setFrame(_:display:)` on `NSWindow`/`NSPanel` must be called on the main thread. `PillWindow` is `@MainActor` (implied via `AppDelegate` wiring) and all callers are already `@MainActor`. The `didChangeScreenParametersNotification` handler also runs on the main thread per AppKit guarantees — no `DispatchQueue.main.async` needed unless explicitly dispatching from a background observer. [CITED: AppKit threading model documentation]

### Pattern: Display Change Observer

```swift
// In PillWindow.init(), after window setup:
NotificationCenter.default.addObserver(
    self,
    selector: #selector(displayConfigurationChanged),
    name: NSApplication.didChangeScreenParametersNotification,
    object: nil
)

// Debounced handler — macOS 14 fires this notification on EVERY window
// minimize/restore, not only on hardware display changes.
private var displayChangeTimer: Timer?

@objc private func displayConfigurationChanged() {
    displayChangeTimer?.invalidate()
    displayChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
        self?.repositionToActiveScreen()
    }
}
```

**Why debounce:** On macOS 14 Sonoma, the OS discards all `NSScreen` objects and rebuilds them — and posts `didChangeScreenParametersNotification` — whenever ANY window is minimized or restored, not just on hardware display changes. Without debouncing, a rapid sequence of notifications would queue up redundant `setFrame` calls. 100ms is enough to coalesce a burst while still feeling instant to the user. [CITED: OpenJDK bug JDK-8353902 documents this macOS 14 behavior; Chromium screen_mac.mm uses same debounce pattern]

### Anti-Patterns to Avoid

- **Using `NSScreen.frame` for anchoring:** Includes Dock and menu bar area. Use `visibleFrame`. [VERIFIED: Apple docs]
- **Calling `setFrame` from a background thread:** AppKit window manipulation requires main thread. All current callers are `@MainActor`; keep it that way.
- **No debounce on the notification handler:** On macOS 14, minimize/restore fires the notification. Without debounce, normal window management causes unnecessary repositioning.
- **Double-guarding with `NSScreen.main` alone as final fallback:** `NSScreen.main` can theoretically return `nil` (unit tests, edge cases). Chain `?? NSScreen.screens[0]` after it — `screens` array is non-empty when a display is attached.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Point-in-rect test | Custom `CGRect.contains` | `NSMouseInRect(pt, frame, false)` | Handles AppKit flipped-coordinate edge pixels correctly |
| Debounce utility | Custom `DispatchWorkItem` cancel/reschedule | `Timer.scheduledTimer` invalidate pattern | Already used in AppKit ecosystem; zero dependencies |
| Screen enumeration | CoreGraphics `CGDisplayCount` | `NSScreen.screens` | Already at the AppKit layer; no extra framework import |

---

## Common Pitfalls

### Pitfall 1: `NSEvent.mouseLocation` coordinate space confusion
**What goes wrong:** Developer confuses `NSEvent.mouseLocation` (global screen coordinates, origin at bottom-left of primary screen) with window-local or view-local coordinates.
**Why it happens:** AppKit uses flipped/non-flipped coordinates in different contexts; SwiftUI uses top-left origin.
**How to avoid:** Use `NSEvent.mouseLocation` directly against `NSScreen.screens[n].frame` — both use the same global coordinate space. Never convert through a view.
**Warning signs:** Pill lands on wrong screen in a left-of-primary monitor arrangement.
[VERIFIED: Apple Developer Documentation — NSEvent.mouseLocation]

### Pitfall 2: `NSEvent.mouseLocation` when cursor is over the menu bar
**What goes wrong:** The cursor position when the menu bar is active is still inside `NSScreen.frame` of the primary display — `frame.contains()` returns true. This is correct behavior: the screen owning the menu bar is the right screen to use.
**Why it happens:** Developers worry menu bar is "outside" visibleFrame. It's inside `frame`, just outside `visibleFrame`.
**How to avoid:** Use `frame` (not `visibleFrame`) for the point-in-screen test; use `visibleFrame` only for the anchor calculation.
[ASSUMED: Based on coordinate system semantics; no specific doc explicitly states this scenario]

### Pitfall 3: Notification fires on window minimize (macOS 14+)
**What goes wrong:** `didChangeScreenParametersNotification` fires when the user minimizes any window, not just on hardware display changes. Without debounce, the pill repositions on every minimize.
**Why it happens:** macOS 14 discards and rebuilds NSScreen objects on minimize/restore (confirmed regression in JDK-8353902).
**How to avoid:** Debounce with a 100ms timer. Idempotent reposition means this is harmless after debounce.
**Warning signs:** Pill jumps to cursor position when user minimizes a different app's window.
[CITED: bugs.openjdk.org/browse/JDK-8353902]

### Pitfall 4: `NSScreen.main` is nil
**What goes wrong:** App crashes in `activeScreen()` when `NSScreen.main ?? NSScreen.screens[0]` is evaluated in a context with no screens (test runner, early launch).
**Why it happens:** `NSScreen.main` returns `Optional<NSScreen>`.
**How to avoid:** Chain double fallback: `screens.first { ... } ?? NSScreen.main ?? NSScreen.screens.first` and guard the outer call site if `screens` is empty.
[VERIFIED: NSScreen.main declaration is `class var main: NSScreen? { get }` — Optional]

### Pitfall 5: `collectionBehavior` and multi-space positioning
**What goes wrong:** `PillWindow` already has `.canJoinAllSpaces` — the window is visible on every Space. After `setFrame`, the window visually jumps to the new position on the correct physical screen even while on a non-active Space.
**Why it happens:** `.canJoinAllSpaces` + `setFrame` is the correct combination; no additional step needed.
**How to avoid:** Nothing special needed — existing `collectionBehavior` already handles this correctly.
[ASSUMED: Based on documented behavior of `.canJoinAllSpaces`; not re-verified in this session]

---

## Code Examples

### Finding active screen (complete helper)
```swift
// [VERIFIED: NSScreen.screens, NSEvent.mouseLocation — Apple Developer Documentation]
private func activeScreen() -> NSScreen {
    let pt = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens[0]
}
```

### Registering the notification observer (in init)
```swift
// [VERIFIED: NotificationCenter.default.addObserver pattern already in MenuBarController]
NotificationCenter.default.addObserver(
    self,
    selector: #selector(displayConfigurationChanged),
    name: NSApplication.didChangeScreenParametersNotification,
    object: nil
)
```

### Call site in handlePress (AppDelegate)
```swift
// Before: state.phase = .recording
// Insert ONE line:
PillWindow.shared.repositionToActiveScreen()
// Then: state.phase = .recording
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSScreen.mainScreen()` (ObjC) | `NSScreen.main` (Swift) | Swift 3 | Property accessor, not method |
| `NSWindow.setFrameOrigin` | `NSWindow.setFrame(_:display:)` | macOS 10.x | Single call sets both origin and size |

**Deprecated/outdated:**
- `NSScreen.mainScreen()`: ObjC name; Swift uses `NSScreen.main` property.

---

## CorrectionWindow Assessment

`CorrectionWindow.positionAboveDock()` is 8 lines, identical structure to `PillWindow.positionAtTop()`. It also hardcodes `NSScreen.main`. The fix is 1 line: replace `NSScreen.main` with `activeScreen()` — but `activeScreen()` would need to be a shared free function or moved to an extension since `CorrectionWindow` is a separate class.

**Recommendation for planner:** Extract `activeScreen()` as a file-private or internal free function at the top of `PillWindow.swift` (or a short `NSScreen+ActiveScreen.swift` extension), then use it in both `PillWindow` and `CorrectionWindow`. The total delta for folding `CorrectionWindow` in is ~5 lines. This is "trivial" per D-03 discretion — fold it in.

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on this phase |
|-----------|---------------------|
| No third-party Swift packages | Confirmed: all needed APIs are AppKit/Foundation |
| `@MainActor` on all UI-touching code | `repositionToActiveScreen()` and the notification handler must be on main actor — already satisfied |
| `final class` with `static let shared` singletons | `PillWindow` already follows this; no change needed |
| No automated tests — manual only | No test files to create; validation is launch + multi-monitor manual test |
| `project.yml` is source of truth for Xcode project | No new files = no `project.yml` changes needed (unless `NSScreen+ActiveScreen.swift` is added — then add to Sources list) |
| macOS 14.0 deployment target | All APIs used (`NSEvent.mouseLocation`, `NSScreen.screens`, `didChangeScreenParametersNotification`) available since macOS 10.x — no availability guards needed |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `NSMouseInRect` and `frame.contains()` behave identically for this use case | Architecture Patterns | Cosmetic — either works; `frame.contains` is safe fallback |
| A2 | Cursor over menu bar is still inside `NSScreen.frame` of the primary display | Pitfall 2 | Pill would use wrong screen when user invokes hotkey while menu bar is active; easy to fix post-discovery |
| A3 | `collectionBehavior = .canJoinAllSpaces` + `setFrame` correctly repositions across physical screens without additional steps | Pitfall 5 | Pill may not reposition correctly on secondary screen; would surface immediately in manual testing |
| A4 | `didChangeScreenParametersNotification` handler runs on main thread | Architecture Patterns | Thread-safety violation; would crash or produce rendering artifacts; easy to guard with `DispatchQueue.main.async` if wrong |

---

## Open Questions

1. **`NSScreen.main` nil guard**: Is `NSScreen.main` ever nil in a normally running menu-bar app?
   - What we know: Declared `Optional<NSScreen>` in Apple headers.
   - What's unclear: Whether it can realistically be nil when the app is running with at least one display.
   - Recommendation: Double-fallback `?? NSScreen.screens.first` costs nothing; include it.

2. **Sidecar display behavior**: When an iPad is used as a Sidecar display, does `NSScreen.screens` include it?
   - What we know: Sidecar presents as a standard display to AppKit.
   - What's unclear: Whether `NSEvent.mouseLocation` can return a point on a Sidecar screen.
   - Recommendation: No special handling needed; the generic `screens.first { frame.contains }` loop handles it transparently.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is pure Swift/AppKit code changes; no external tools, CLIs, or services required beyond the existing Xcode build chain.

---

## Validation Architecture

No automated test infrastructure exists in this project (CLAUDE.md: "There are no automated tests; all testing is manual via the running app"). The `workflow.nyquist_validation` setting is absent from `.planning/config.json` (not present), so the section is nominally enabled — but with a manual-only project, test automation is inapplicable.

### Manual Test Protocol (Wave 0 Gate)

| REQ ID | Test Scenario | Pass Criterion |
|--------|---------------|----------------|
| DISPLAY-01 | Two monitors. Cursor on secondary. Press hotkey. | Pill appears on secondary screen. |
| DISPLAY-01 | Two monitors. Cursor on primary. Press hotkey. | Pill appears on primary screen. |
| DISPLAY-01 | Cursor in menu bar on primary. Press hotkey. | Pill appears on primary screen (not missing). |
| DISPLAY-01 | Single monitor. Press hotkey. | Pill appears normally, no crash. |
| DISPLAY-02 | Pill on secondary. Disconnect secondary. | Pill moves to primary screen, not stranded off-screen. |
| DISPLAY-02 | Reconnect secondary monitor. | Pill stays on current screen (no spurious jump). |
| DISPLAY-02 | Minimize an unrelated window (macOS 14 regression check). | Pill does NOT reposition. |

---

## Security Domain

No security-sensitive APIs or data involved. This phase touches only window geometry and display enumeration — no authentication, secrets, network, or user data. ASVS categories are not applicable.

---

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation — NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/1533380-mouselocation)
- [Apple Developer Documentation — NSScreen](https://developer.apple.com/documentation/appkit/nsscreen)
- [Apple Developer Documentation — NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/1388369-visibleframe)
- [Apple Developer Documentation — NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
- Existing codebase: `PillWindow.swift`, `CorrectionWindow.swift`, `ListenToMeApp.swift` — read directly

### Secondary (MEDIUM confidence)
- [OpenJDK JDK-8353902 — NSScreen leaked on minimize (macOS 14 notification behavior)](https://bugs.openjdk.org/browse/JDK-8353902) — documents macOS 14 notification-on-minimize behavior
- [Chromium screen_mac.mm — debounce pattern for display notifications](https://cocalc.com/github/chromium/chromium/blob/main/ui/display/mac/screen_mac.mm)

### Tertiary (LOW confidence)
- WebSearch results confirming `NSMouseInRect` idiom for multi-screen point containment testing

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are stable AppKit, verified against Apple docs
- Architecture: HIGH — pattern derived directly from existing code in the repo
- Pitfalls: MEDIUM — macOS 14 notification behavior verified via secondary source; coordinate space assumptions flagged as ASSUMED

**Research date:** 2026-05-05
**Valid until:** 2026-11-05 (stable AppKit APIs; macOS 14 behavior note remains relevant through at least macOS 15)
