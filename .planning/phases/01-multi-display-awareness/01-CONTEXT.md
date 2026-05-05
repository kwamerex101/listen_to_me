# Phase 1: Multi-Display Awareness - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

The pill (`PillWindow`, an `NSPanel`) must always show on the screen the user is actively working on, and recover gracefully when monitors are added, removed, or rearranged. Scope is limited to repositioning logic — no changes to pill appearance, animations, focus behavior, or any other system. The correction popover (`CorrectionWindow`) is a separate window and out of scope for this phase but should pick up the same active-screen logic if trivial; if not, it stays on `NSScreen.main` for now and gets its own ticket.

</domain>

<decisions>
## Implementation Decisions

### Active screen definition

- **D-01:** "Active screen" = the screen containing `NSEvent.mouseLocation` at the moment the pill needs to show. Falls back to `NSScreen.main` only if the cursor isn't over any connected screen (rare; happens during rapid display config changes).
- **D-02:** Do **not** use frontmost-app's main window position. It's harder to query (needs AX), unreliable for windowless apps, and the cursor is the user's "I am here" signal.

### Reposition cadence

- **D-03:** Reposition only at two moments:
  1. Right before transitioning from `.idle` into any visible phase (`.recording`, `.transcribing`, `.polishing`, `.success`, `.error`, `.correcting`).
  2. On `NSApplication.didChangeScreenParametersNotification` (display add/remove/rearrange).
- **D-04:** Do **not** continuously track the cursor. No mouse-move observer, no per-frame updates. Idle pill stays on whichever screen the last dictation finished on until a new dictation begins or monitors change.

### Idle pill behavior

- **D-05:** Single instance. One `PillWindow`, one pill, on the active screen. Do not mirror across all connected displays.
- **D-06:** When the user moves cursor to a different screen and starts a new dictation there, the pill repositions to that screen at the moment of the press → recording phase transition (per D-03 #1).

### Claude's Discretion

- Exact insertion point for the reposition call. The most likely site is in `AppDelegate.handlePress()` immediately before setting `state.phase = .recording`, or via a hook on phase transitions. Planner picks the cleanest point.
- Whether to refactor `PillWindow.positionAtTop()` (which despite its name actually anchors to the bottom — that misnomer is fair game to clean up) or add a sibling method. Planner's call.
- Whether `CorrectionWindow` gets the same active-screen logic in this phase (cheap hop) or stays a follow-on ticket. If trivial during implementation, fold it in; otherwise note as deferred.
- Observer lifecycle for `didChangeScreenParametersNotification` — `NotificationCenter.default.addObserver` on `PillWindow.shared` at init time is the obvious shape, but the planner should verify it doesn't conflict with the panel's existing notification flow.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Codebase
- `ListenToMe/UI/PillWindow.swift` — Current `NSPanel` subclass. Has a `positionAtTop()` method (misnomer — actually positions at bottom) called only from `showPersistent()`. This is the primary file to change.
- `ListenToMe/UI/CorrectionWindow.swift` — Sibling NSPanel for the correction popover, also has its own `positionAboveDock()` method. Mention if planner decides to fold same logic in here.
- `ListenToMe/ListenToMeApp.swift` — `AppDelegate.handlePress()` at line ~85, the most likely call site for "reposition before showing pill".
- `ListenToMe/State/AppState.swift` — `Phase` enum; transitions trigger UI changes. Reference for the "moments the pill becomes visible" list.
- `.planning/codebase/ARCHITECTURE.md` — Pill window architecture overview.
- `.planning/codebase/STRUCTURE.md` — `NSPanel` subclasses and where they live.

### macOS APIs (developer.apple.com)
- `NSEvent.mouseLocation` — class property returning the global cursor location in screen coordinates. Returns `NSPoint` even when the cursor is over the menu bar or off any screen.
- `NSScreen.screens` — all connected screens. Iterate to find the one whose `frame` contains `NSEvent.mouseLocation`.
- `NSScreen.visibleFrame` — the frame minus Dock and menu bar (and notch on M-series). Use this for positioning, not `frame`.
- `NSApplication.didChangeScreenParametersNotification` — posted on monitor connect/disconnect/rearrange. Observe via `NotificationCenter.default`.

### Project planning
- `.planning/REQUIREMENTS.md` §Display — DISPLAY-01 and DISPLAY-02 requirement text.
- `.planning/ROADMAP.md` Phase 1 — full success criteria (5 of them — re-read before planning).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PillWindow.shared.showPersistent()` already calls `positionAtTop()` once at app launch. The same method (renamed or extended) is the natural target for the reposition call.
- `NotificationCenter.default.addObserver` pattern is already used in `MenuBarController` for `.phaseChanged` — same shape works for `didChangeScreenParametersNotification`.
- `NSScreen.main` already used as fallback in `MainWindowController` and `PillWindow.positionAtTop` — same fallback strategy applies here.

### Established Patterns
- `@MainActor` annotation on `AppDelegate`, `AppState`, and the menu bar controller. Window repositioning runs on the main actor; no async needed.
- Singletons (`Foo.shared`) for system services. `PillWindow.shared` is the only instance — no per-screen multiplication needed (per D-05).
- Phase enum drives UI state. Reposition logic hooks into phase transitions, not direct view code.

### Integration Points
- **Insertion site for reposition-before-show:** `AppDelegate.handlePress()` in `ListenToMe/ListenToMeApp.swift:~85`. Right before `state.phase = .recording`. The pill is currently hidden at idle (12pt tall, near-invisible breath dot); it becomes "visible" at recording onset.
- **Display-config observer:** Initialize once in `PillWindow.init()` or in `AppDelegate.applicationDidFinishLaunching` after `PillWindow.shared.showPersistent()`. Either is fine.
- **Method to call:** A single `PillWindow.repositionToActiveScreen()` (or rename `positionAtTop` and have it default to the active screen). Idempotent.

### Existing fragility
- The current `positionAtTop()` is named for its content (the pill renders at the bottom of the window's content area, hence the window itself is anchored at the bottom of `visibleFrame`, despite the method name). The naming is confusing. If we touch this method, rename it.

</code_context>

<specifics>
## Specific Ideas

- User explicitly mentioned the pain: "If I open it up on one monitor and I am working on the other monitor the pill doesn't move automatically to the other monitor." That's the failure mode the success criteria target.
- User is on multi-monitor (clearly), and the pill being on the wrong screen is daily friction.

</specifics>

<deferred>
## Deferred Ideas

- **Continuous cursor tracking** — captured as the rejected option in question 2. Could be added later as a "follow my cursor always" preference if the per-press repositioning proves insufficient. Not a near-term need.
- **Pill mirrored across all screens** — captured as the rejected option in question 3. Out of scope; would require multiple `NSPanel` instances and complex correction-popover plumbing.
- **`CorrectionWindow` active-screen logic** — possibly folded into this phase if trivial, otherwise its own follow-on. Note in PLAN.md.
- **Renaming `positionAtTop` for clarity** — minor cleanup ride-along during implementation. Not a separate phase.

</deferred>

---

*Phase: 1-Multi-Display-Awareness*
*Context gathered: 2026-05-05*
