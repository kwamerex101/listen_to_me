---
phase: 01-multi-display-awareness
plan: "01"
subsystem: UI / display management
tags: [multi-display, nsscreen, appkit, window-positioning, debounce]
dependency_graph:
  requires: []
  provides:
    - activeScreen() helper (module-internal)
    - PillWindow.repositionToActiveScreen()
    - PillWindow display-change observer (100ms debounced)
    - CorrectionWindow active-screen positioning
  affects:
    - ListenToMe/UI/PillWindow.swift
    - ListenToMe/UI/CorrectionWindow.swift
    - ListenToMe/ListenToMeApp.swift
    - project.yml
    - ListenToMe/Info.plist
    - SUPPORT.md
tech_stack:
  added: []
  patterns:
    - "100ms Timer.scheduledTimer debounce for AppKit notification storms (macOS 14 JDK-8353902)"
    - "Module-internal free function shared across related AppKit windows in same module"
    - "@MainActor wrapper in Timer closure to satisfy actor-isolation checker"
key_files:
  created: []
  modified:
    - path: ListenToMe/UI/PillWindow.swift
      delta: "Added activeScreen() free function; renamed positionAtTop→repositionToActiveScreen (internal); added displayChangeTimer property; added 100ms debounced displayConfigurationChanged observer"
    - path: ListenToMe/UI/CorrectionWindow.swift
      delta: "positionAboveDock() now calls activeScreen() instead of NSScreen.main"
    - path: ListenToMe/ListenToMeApp.swift
      delta: "One-line insertion: PillWindow.shared.repositionToActiveScreen() immediately before state.phase = .recording in handlePress()"
    - path: project.yml
      delta: "CFBundleShortVersionString 0.6.1 → 0.7.0; CFBundleVersion 6 → 7"
    - path: ListenToMe/Info.plist
      delta: "CFBundleShortVersionString 0.6.1 → 0.7.0; CFBundleVersion 6 → 7"
    - path: SUPPORT.md
      delta: "Known limitations header updated v0.6.1 → v0.7.0"
decisions:
  - "activeScreen() declared as module-internal free function (not private/fileprivate) so CorrectionWindow.swift in the same module can call it without duplicating the logic"
  - "Triple fallback chain: screens.first{contains} ?? .main ?? .screens.first ?? .screens[0] — last element is unreachable dev-time invariant keeping return type non-optional"
  - "100ms debounce via Timer.scheduledTimer chosen over DispatchWorkItem; matches AppKit run-loop model and invalidation is straightforward"
  - "No didChangeScreenParametersNotification observer on CorrectionWindow — transient window repositions on every show(); disconnect-while-open is an accepted edge case"
metrics:
  duration: "~15 minutes"
  completed_date: "2026-05-05"
  tasks_completed: 3
  tasks_total: 4
  files_changed: 6
---

# Phase 01 Plan 01: Multi-Display Awareness (Tasks 1-3) Summary

**One-liner:** Pill and correction windows now anchor to the cursor's screen via `NSEvent.mouseLocation`, with a 100ms-debounced display-change observer absorbing the macOS 14 minimize/restore notification storm.

## What Was Built

### Task 1 — PillWindow active-screen machinery (c2baeca)

- **`activeScreen()` free function** (module-internal, `@MainActor`) added before `PillWindow` class declaration in `PillWindow.swift`. Uses `NSEvent.mouseLocation` + `NSMouseInRect` against `screen.frame` (not `visibleFrame` — cursor over menu bar is inside `frame` but outside `visibleFrame`). Triple fallback: `screens.first{contains} ?? .main ?? .screens.first ?? .screens[0]`.
- **`repositionToActiveScreen()`** replaces `positionAtTop()`. Visibility raised from `private` to internal so callers outside the file can invoke it. Uses `activeScreen()` for screen resolution; `visibleFrame` math unchanged (anchors bottom-center, +4pt above Dock).
- **`showPersistent()`** updated to call `repositionToActiveScreen()`.
- **`displayChangeTimer: Timer?`** property added. **`displayConfigurationChanged()`** `@objc` handler added: invalidates prior timer, schedules a 100ms `Timer.scheduledTimer` that calls `repositionToActiveScreen()` inside `Task { @MainActor in ... }` to satisfy the actor-isolation checker.
- **`NotificationCenter.default.addObserver`** wired in `private init()` for `NSApplication.didChangeScreenParametersNotification`.

### Task 2 — handlePress and CorrectionWindow (30dd346)

- **`ListenToMeApp.swift`**: One line inserted immediately before `state.phase = .recording` in `handlePress()`: `PillWindow.shared.repositionToActiveScreen()`. This resolves DISPLAY-01 — dictation always starts on the cursor's screen.
- **`CorrectionWindow.swift`**: `positionAboveDock()` replaced `guard let screen = NSScreen.main else { return }` with `let screen = activeScreen()`. No other changes; the rest of the geometry is unchanged.

### Task 3 — Version bump 0.6.1 → 0.7.0 (a24aded)

- `project.yml`: `CFBundleShortVersionString` → `"0.7.0"`, `CFBundleVersion` → `"7"`
- `ListenToMe/Info.plist`: same fields updated
- `SUPPORT.md`: "Known limitations in v0.6.1" → "Known limitations in v0.7.0"
- `xcodegen generate` run to propagate `project.yml` → `.xcodeproj`

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 | c2baeca | feat(01-01): add activeScreen() helper, rename positionAtTop→repositionToActiveScreen, wire display-change observer |
| 2 | 30dd346 | feat(01-01): wire repositionToActiveScreen() into handlePress and CorrectionWindow |
| 3 | a24aded | chore(01-01): bump version 0.6.1 → 0.7.0 |

## Code-level Invariants Verified

- `grep -c 'positionAtTop' PillWindow.swift` → 1 (doc comment only; function renamed)
- `grep -c 'repositionToActiveScreen' PillWindow.swift` → 3 (declaration + call from showPersistent + call in timer handler)
- `grep -c 'didChangeScreenParametersNotification' PillWindow.swift` → 2 (addObserver + handler)
- `grep -c 'func activeScreen' PillWindow.swift` → 1
- `grep -c 'scheduledTimer' PillWindow.swift` → 1
- `NSScreen.main` in PillWindow non-comments → 1 (only inside activeScreen() fallback)
- `NSScreen.main` in CorrectionWindow non-comments → 0
- `./scripts/build.sh` → BUILD SUCCEEDED (all 3 tasks)

## Deviations from Plan

None — plan executed exactly as written. The `positionAtTop` doc-comment reference (1 count from `grep -c`) is expected per plan (it documents the rename history in the replacement method's docstring).

## Task 4 Status

**AWAITING HUMAN VERIFICATION** — Task 4 is `type="checkpoint:human-verify"`. Manual multi-monitor testing required against ROADMAP Phase 1 SC-1 through SC-5.

## Known Stubs

None. All wiring is live; no placeholder data flows to UI.

## Threat Flags

None. This plan touches only window geometry and display enumeration per the threat model. No new trust boundaries introduced.

## Lessons Learned / Reusable Patterns

1. **100ms debounce for AppKit notification storms (macOS 14):** `NSApplication.didChangeScreenParametersNotification` fires on every minimize/restore on macOS 14 (JDK-8353902). Use `Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false)` + `invalidate()` on each invocation to coalesce bursts. Wrap the callback body in `Task { @MainActor in ... }` to satisfy the actor-isolation checker since Timer callbacks are not implicitly `@MainActor`.

2. **activeScreen() as module-internal free function:** When two AppKit windows in the same module need the same screen-resolution logic, a free function at internal visibility (Swift default) avoids duplication without introducing a helper class or utility file. Place it in the file of the primary owner (PillWindow.swift here) before the class declaration.

3. **NSMouseInRect with frame, not visibleFrame for cursor-containment:** The cursor can be positioned in the menu bar area — which is inside `screen.frame` but outside `screen.visibleFrame`. Always use `frame` for the point-in-screen containment test, and `visibleFrame` for the actual window anchor calculation.

## Self-Check: PASSED

All commits verified present. All files verified modified with correct content. Build succeeded end-to-end.
