---
phase: 01-multi-display-awareness
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ListenToMe/UI/PillWindow.swift
  - ListenToMe/UI/CorrectionWindow.swift
  - ListenToMe/ListenToMeApp.swift
  - project.yml
  - ListenToMe/Info.plist
  - SUPPORT.md
autonomous: false
requirements:
  - DISPLAY-01
  - DISPLAY-02

must_haves:
  truths:
    - "When the pill becomes visible, it appears on the screen containing the cursor."
    - "If the cursor is on monitor 2, the pill anchors to monitor 2's visibleFrame; if on monitor 1, monitor 1's."
    - "Disconnecting the monitor the pill currently lives on causes the pill to reposition to a remaining monitor within ~1s."
    - "The pill never overlaps the Dock, menu bar, or notch on any screen (uses visibleFrame for anchoring)."
    - "When NSEvent.mouseLocation isn't over any screen, the pill falls back to NSScreen.main, then NSScreen.screens.first."
    - "Minimizing or restoring an unrelated window does NOT cause the pill to jump (debounce in effect)."
    - "CorrectionWindow opens on the same active screen as the pill it overlays."
  artifacts:
    - path: "ListenToMe/UI/PillWindow.swift"
      provides: "activeScreen() helper, repositionToActiveScreen(), debounced display-change observer"
      contains: "func activeScreen"
    - path: "ListenToMe/UI/PillWindow.swift"
      provides: "Notification observer for didChangeScreenParametersNotification"
      contains: "didChangeScreenParametersNotification"
    - path: "ListenToMe/UI/CorrectionWindow.swift"
      provides: "Same active-screen logic for correction popover"
      contains: "activeScreen"
    - path: "ListenToMe/ListenToMeApp.swift"
      provides: "Reposition call before pill becomes visible in handlePress"
      contains: "repositionToActiveScreen"
  key_links:
    - from: "ListenToMe/ListenToMeApp.swift handlePress()"
      to: "PillWindow.shared.repositionToActiveScreen()"
      via: "direct call before state.phase = .recording"
      pattern: "repositionToActiveScreen"
    - from: "PillWindow init"
      to: "NSApplication.didChangeScreenParametersNotification"
      via: "NotificationCenter.default.addObserver"
      pattern: "didChangeScreenParametersNotification"
    - from: "displayConfigurationChanged handler"
      to: "repositionToActiveScreen()"
      via: "100ms Timer.scheduledTimer debounce"
      pattern: "scheduledTimer.*0.1"
---

<objective>
Make the ListenToMe pill follow the screen the user is actively working on.

Purpose: Daily friction — the pill currently anchors to `NSScreen.main` (always primary) regardless of where the user is working. On multi-monitor setups, dictating on monitor 2 puts the pill on monitor 1, out of view.

Output:
- `PillWindow` repositions to the screen containing `NSEvent.mouseLocation` at the moment a dictation starts (DISPLAY-01).
- `PillWindow` re-anchors automatically when monitors are added, removed, or rearranged, with a 100ms debounce to absorb the macOS 14 minimize/restore notification storm (DISPLAY-02).
- `CorrectionWindow` follows the same active-screen logic so the correction popover lands on the correct monitor (folded in per RESEARCH.md — ~5 lines).
- Misnamed `PillWindow.positionAtTop()` renamed to `repositionToActiveScreen()` (it actually anchors at the bottom of `visibleFrame`).
- Version bumped from 0.6.1 → 0.7.0 (feature → minor per CLAUDE.md versioning policy).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-multi-display-awareness/01-CONTEXT.md
@.planning/phases/01-multi-display-awareness/01-RESEARCH.md
@.planning/codebase/ARCHITECTURE.md
@.planning/codebase/CONVENTIONS.md
@CLAUDE.md
@ListenToMe/UI/PillWindow.swift
@ListenToMe/UI/CorrectionWindow.swift
@ListenToMe/ListenToMeApp.swift

<interfaces>
<!-- Pre-existing contracts the executor needs. No exploration required. -->

From `ListenToMe/UI/PillWindow.swift` (current shape — to be modified):
```swift
final class PillWindow: NSPanel {
    static let shared = PillWindow()
    static let windowSize = NSSize(width: 480, height: 260)
    private init() { ... }                       // line 10
    func showPersistent()                        // line 35 — calls positionAtTop()
    private func positionAtTop()                 // line 40 — uses NSScreen.main; misnamed (anchors at bottom)
    func setInteractive(_ enabled: Bool)         // line 53
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

From `ListenToMe/UI/CorrectionWindow.swift` (current shape — to be modified):
```swift
final class CorrectionWindow: NSPanel {
    static let shared = CorrectionWindow()
    static let windowSize = NSSize(width: 540, height: 96)
    private init() { ... }                       // line 16
    func show(initialText:onApply:onCancel:)     // line 37 — calls positionAboveDock()
    func dismiss()                               // line 65
    private func positionAboveDock()             // line 72 — uses NSScreen.main
}
```

From `ListenToMe/ListenToMeApp.swift` (current shape — insertion site):
```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private func handlePress() {                 // line 92
        // line 97: if case .recording = state.phase { return }
        // line 113: state.phase = .recording   <-- INSERT reposition call IMMEDIATELY BEFORE this
    }
}
```

AppKit APIs (already imported):
```swift
NSEvent.mouseLocation       // class var: NSPoint, global screen coords
NSScreen.screens            // class var: [NSScreen], all connected
NSScreen.main               // class var: NSScreen?  -- Optional!
NSScreen.frame              // var: NSRect, full screen including menu/Dock
NSScreen.visibleFrame       // var: NSRect, minus menu bar / Dock / notch
NSMouseInRect(_:_:_:)       // func: idiomatic point-in-rect for AppKit coords
NSApplication.didChangeScreenParametersNotification  // notification name
NotificationCenter.default.addObserver(_:selector:name:object:)
Timer.scheduledTimer(withTimeInterval:repeats:block:)  // for debounce
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add active-screen helper, rename positionAtTop, wire display-change observer in PillWindow</name>
  <files>ListenToMe/UI/PillWindow.swift</files>
  <action>
Modify `ListenToMe/UI/PillWindow.swift` end-to-end:

1. **Add file-private free function** at the top of the file (after `import SwiftUI`, before `final class PillWindow`). This is shared with `CorrectionWindow` per RESEARCH.md "CorrectionWindow Assessment" — folding it in is ~5 lines and explicitly recommended.

```swift
/// Returns the NSScreen currently containing the cursor, with double-fallback
/// to NSScreen.main and then NSScreen.screens.first. Used by both PillWindow
/// and CorrectionWindow to anchor on the active monitor (DISPLAY-01).
@MainActor
func activeScreen() -> NSScreen {
    let pt = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens.first
        ?? NSScreen.screens[0]   // dev-time invariant: at least one screen attached
}
```

   - Use `frame` (not `visibleFrame`) for the contains-test per RESEARCH.md Pitfall 2: cursor over the menu bar is inside `frame` but outside `visibleFrame`; that screen is the right one.
   - Mark `@MainActor` because `NSScreen.main` and `NSScreen.screens` are documented main-thread-only and callers are already main-actor.

2. **Rename `positionAtTop()` to `repositionToActiveScreen()`** and change visibility from `private` to `func` (internal) so it's callable from `AppDelegate.handlePress()`. Replace the `NSScreen.main` reference with `activeScreen()`. Keep the `visibleFrame` math unchanged (still anchors to bottom-center, +4pt above Dock — that's the existing behavior the user already accepted).

```swift
/// Reposition the window to the currently active screen (cursor screen).
/// Despite the prior name `positionAtTop()`, the window anchors to the BOTTOM
/// of `visibleFrame` — the visible pill inside is rendered at the bottom of
/// the SwiftUI content area. Called once at launch (`showPersistent`),
/// before each dictation (DISPLAY-01), and on display config changes (DISPLAY-02).
func repositionToActiveScreen() {
    let screen = activeScreen()
    let visible = screen.visibleFrame
    let s = Self.windowSize
    let x = visible.midX - s.width / 2
    let y = visible.minY + 4    // just above the Dock
    setFrame(NSRect(x: x, y: y, width: s.width, height: s.height), display: true)
}
```

3. **Update `showPersistent()`** to call the renamed method:
```swift
func showPersistent() {
    repositionToActiveScreen()
    orderFrontRegardless()
}
```

4. **Add display-change observer** inside `private init()`, after the existing `contentView?.addSubview(host)` line and before `}`. Use `#selector` syntax which requires `@objc`-marked handler. Register on `NotificationCenter.default`.

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(displayConfigurationChanged),
    name: NSApplication.didChangeScreenParametersNotification,
    object: nil
)
```

   No `removeObserver` needed: `PillWindow.shared` is a singleton with app-lifetime scope. (NSObject subclasses inherit auto-removal on dealloc on macOS 10.11+, and this object never deallocates.)

5. **Add debounced handler and timer property** as members of `PillWindow`. Place `displayChangeTimer` near the top of the class (after `static let windowSize`); place the `@objc` handler after `setInteractive` and before the two `canBecomeKey`/`canBecomeMain` overrides.

```swift
/// Debounce timer for `didChangeScreenParametersNotification`. macOS 14 fires
/// this notification on every window minimize/restore (JDK-8353902), not just
/// on hardware display changes. 100ms coalesces a burst into a single reposition.
private var displayChangeTimer: Timer?

@objc private func displayConfigurationChanged() {
    displayChangeTimer?.invalidate()
    displayChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
        Task { @MainActor in
            self?.repositionToActiveScreen()
        }
    }
}
```

   Notes:
   - `Timer.scheduledTimer`'s callback runs on the run loop that scheduled it (main run loop here, since the observer fires on the main thread per AppKit), but the closure is not implicitly `@MainActor`. Wrap the call in `Task { @MainActor in ... }` to satisfy the actor-isolation checker for `repositionToActiveScreen()`.
   - `[weak self]` to avoid extending the timer's hold beyond the (singleton) window's lifetime; harmless here but keeps the pattern consistent with project conventions (`async/await` weak-self pattern in `CONVENTIONS.md`).

6. **Do not change** any other method, the `collectionBehavior`, the `level`, or any styling. Surgical change only.
  </action>
  <verify>
    <automated>
swift -frontend -parse ListenToMe/UI/PillWindow.swift -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos14.0 2>&1 | tee /tmp/pillwindow-parse.log; test ! -s /tmp/pillwindow-parse.log
# Plus full build:
./scripts/build.sh 2>&1 | tail -40
    </automated>
  </verify>
  <done>
    - `PillWindow.swift` compiles cleanly via `./scripts/build.sh`.
    - `grep -c 'positionAtTop' ListenToMe/UI/PillWindow.swift` returns 0 (renamed everywhere).
    - `grep -c 'repositionToActiveScreen' ListenToMe/UI/PillWindow.swift` returns >= 2 (declaration + call from `showPersistent`).
    - `grep -c 'didChangeScreenParametersNotification' ListenToMe/UI/PillWindow.swift` returns 1.
    - `grep -c 'func activeScreen' ListenToMe/UI/PillWindow.swift` returns 1.
    - `grep -c 'scheduledTimer' ListenToMe/UI/PillWindow.swift` returns 1.
    - `NSScreen.main` no longer the sole anchor — `grep 'NSScreen.main' ListenToMe/UI/PillWindow.swift` only appears inside `activeScreen()` as the second-tier fallback.
    - App launches without crash; pill visible at bottom-center of cursor's screen on first run.
  </done>
</task>

<task type="auto">
  <name>Task 2: Wire reposition call into handlePress and apply same logic to CorrectionWindow</name>
  <files>ListenToMe/ListenToMeApp.swift, ListenToMe/UI/CorrectionWindow.swift</files>
  <action>
**Part A — `ListenToMe/ListenToMeApp.swift`** (insertion in `handlePress()`):

1. Locate `handlePress()` at line 92. Find the existing line:
```swift
state.phase = .recording
```
   This currently sits at line 113 (after `_ = try AudioRecorder.shared.start()` and `recordingStartedAt = Date()`).

2. **Insert ONE line immediately before** `state.phase = .recording`:
```swift
PillWindow.shared.repositionToActiveScreen()
```

   Why this exact site: per CONTEXT.md D-03 #1, repositioning happens "right before transitioning from `.idle` into any visible phase." The first such transition in `handlePress` is to `.recording`. Per RESEARCH.md, all callers are already `@MainActor` and `setFrame(_:display:)` is main-thread safe — no async wrapping.

3. **Do not** insert before `state.phase = .error(...)` paths in `handlePress` — error states still show the pill, but those errors only occur when (a) mic permission is missing or (b) `AudioRecorder.shared.start()` throws. In both cases the pill stays where it last was (idle on whatever screen the last dictation was on); a one-line reposition before the error transition is acceptable polish but **not required by D-03**. Skip it for surgical scope.

4. **Do not** insert into `handleRelease`, `handlePillTap`, `applyCorrection`, etc. The `.recording` transition in `handlePress` is the ONLY entry into a non-idle phase per the AppDelegate code; all subsequent visible phases (`.transcribing`, `.polishing`, `.success`, `.error`, `.correcting`) are downstream of that single transition. The pill is already on the right screen by then. (Verified by reading lines 134-237 of `ListenToMeApp.swift`: `handleRelease` only transitions from `.recording` → `.transcribing` → `.polishing`/`.success`, never from `.idle`.)

**Part B — `ListenToMe/UI/CorrectionWindow.swift`** (apply shared `activeScreen()` to `positionAboveDock`):

1. Open `ListenToMe/UI/CorrectionWindow.swift`. Locate `positionAboveDock()` at line 72.

2. Replace the body — keep the method name (it's accurate for this window's purpose) but swap `NSScreen.main` for `activeScreen()`:

```swift
private func positionAboveDock() {
    let screen = activeScreen()       // file-private free function from PillWindow.swift
    let visible = screen.visibleFrame
    let s = Self.windowSize
    let x = visible.midX - s.width / 2
    let y = visible.minY + 50
    setFrame(NSRect(x: x, y: y, width: s.width, height: s.height), display: true)
}
```

   Notes:
   - `activeScreen()` is file-private to `PillWindow.swift`. Since both files live in the same module (`ListenToMe`), change its visibility to **internal** (drop any access modifier — Swift default is internal). Adjust Task 1's helper declaration accordingly: `func activeScreen() -> NSScreen` (no `private`, no `fileprivate`).
   - Remove the `guard let screen = NSScreen.main else { return }` early return — `activeScreen()` always returns non-optional, so the guard is dead code.
   - Method stays `private` to `CorrectionWindow`. No need to expose it.

3. **Do not add** a `didChangeScreenParametersNotification` observer to `CorrectionWindow`. The correction popover is transient (shown only during `.correcting`, dismissed on apply/cancel), and `show()` calls `positionAboveDock()` on every open. If the user disconnects a monitor while the popover is open (extreme edge case), the popover may end up off-screen until next open — accept this; user can press Esc to cancel. Documented as deferred in this plan's "Out of Scope" note below.

**Verification of insertion site (run after edits):**
```bash
grep -n 'repositionToActiveScreen\|state.phase = .recording' ListenToMe/ListenToMeApp.swift
```
Expected: `repositionToActiveScreen` line appears IMMEDIATELY BEFORE `state.phase = .recording` in `handlePress()`. They should be on consecutive lines.
  </action>
  <verify>
    <automated>
./scripts/build.sh 2>&1 | tail -20
# Insertion-site invariant: reposition call is the line just before .recording transition.
python3 -c "
import re
src = open('ListenToMe/ListenToMeApp.swift').read()
m = re.search(r'PillWindow\.shared\.repositionToActiveScreen\(\)\s*\n\s*state\.phase = \.recording', src)
assert m, 'reposition call must immediately precede state.phase = .recording'
print('insertion-site OK')
"
# CorrectionWindow uses activeScreen helper, not NSScreen.main directly:
grep -v '^//' ListenToMe/UI/CorrectionWindow.swift | grep -v '^ *//' | grep -c 'NSScreen.main'
# expected: 0
grep -c 'activeScreen' ListenToMe/UI/CorrectionWindow.swift
# expected: >= 1
    </automated>
  </verify>
  <done>
    - `./scripts/build.sh` succeeds; produces a runnable `.app`.
    - `handlePress()` calls `repositionToActiveScreen()` on the line directly before `state.phase = .recording`.
    - `CorrectionWindow.positionAboveDock()` calls `activeScreen()` (no `NSScreen.main` reference outside the helper's fallback chain).
    - Launching the app and pressing the hotkey on a non-primary monitor places the pill on that monitor.
  </done>
</task>

<task type="auto">
  <name>Task 3: Bump version 0.6.1 → 0.7.0 in project.yml, Info.plist, and SUPPORT.md</name>
  <files>project.yml, ListenToMe/Info.plist, SUPPORT.md</files>
  <action>
Per CLAUDE.md versioning policy: **feature → minor bump**. Multi-display awareness is a user-visible feature — bump 0.6.1 → 0.7.0.

1. **`project.yml`** — find any line containing `0.6.1` (likely under `MARKETING_VERSION` or `CFBundleShortVersionString`). Replace with `0.7.0`. If `CURRENT_PROJECT_VERSION` is also tracked (build number), increment it by 1 (or set to a sensible next value).

2. **`ListenToMe/Info.plist`** — find `<key>CFBundleShortVersionString</key>` followed by `<string>0.6.1</string>` and replace with `<string>0.7.0</string>`. If `CFBundleVersion` is also `0.6.1`, bump to `0.7.0` (or +1 build number if it's a separate integer).

3. **`SUPPORT.md`** — find any `0.6.1` reference and update to `0.7.0`. If it references a "current version" or "latest version" line, update that line.

4. **Regenerate the Xcode project** to propagate `project.yml` → `.xcodeproj`:
```bash
xcodegen generate
```

5. **Verify** by reading the resulting project.yml, Info.plist, and SUPPORT.md to confirm no `0.6.1` references remain (except possibly in changelog/historical context — leave those alone).

If any of `project.yml`, `Info.plist`, or `SUPPORT.md` does NOT currently contain `0.6.1`, that's fine — note it and move on; only update files where the prior version actually appears.
  </action>
  <verify>
    <automated>
# After edits, no remaining 0.6.1 in version-bearing files (excluding changelog/history mentions):
grep -l '0\.6\.1' project.yml ListenToMe/Info.plist SUPPORT.md 2>/dev/null
# Expected: empty (no output)
grep -c '0\.7\.0' project.yml ListenToMe/Info.plist SUPPORT.md 2>/dev/null | grep -v ':0$'
# Expected: at least one file shows >= 1 match
xcodegen generate 2>&1 | tail -5
./scripts/build.sh 2>&1 | tail -5
    </automated>
  </verify>
  <done>
    - All three files reference `0.7.0` (where they previously referenced `0.6.1`).
    - `xcodegen generate` succeeds without errors.
    - `./scripts/build.sh` succeeds with the bumped version.
    - The built `.app`'s `Info.plist` shows `CFBundleShortVersionString = 0.7.0`.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: Manual multi-monitor verification against ROADMAP Phase 1 success criteria</name>
  <what-built>
- `PillWindow.repositionToActiveScreen()` resolves the active screen from `NSEvent.mouseLocation`, falls back to `NSScreen.main` then `NSScreen.screens.first`.
- `AppDelegate.handlePress()` calls `repositionToActiveScreen()` immediately before `state.phase = .recording`.
- `PillWindow` observes `NSApplication.didChangeScreenParametersNotification` with a 100ms debounce.
- `CorrectionWindow.positionAboveDock()` uses the same shared `activeScreen()` helper.
- Version bumped to 0.7.0.
  </what-built>
  <how-to-verify>
**Setup:** Two monitors connected. Build and install the latest version: `./scripts/build.sh && ./scripts/install.sh`. Launch ListenToMe. Confirm the pill is visible (compact idle state at the bottom of the active screen).

Walk through each ROADMAP Phase 1 success criterion in order. Report PASS/FAIL for each — note any monitor that misbehaves.

---

**SC-1 (DISPLAY-01) — Cursor on monitor 2 → pill on monitor 2:**
1. Move the cursor onto monitor 2 (any app — TextEdit, VS Code, Slack).
2. Press and hold the dictation hotkey (Fn+Cmd by default).
3. **Expected:** Pill visibly appears at the bottom-center of monitor 2's `visibleFrame`, NOT monitor 1.
4. Release hotkey, let the dictation complete normally.

**SC-2 (DISPLAY-01 cross-monitor handoff) — Pill follows new dictation:**
1. With the pill visible from SC-1 on monitor 2 (during `.success` phase, ~3s window).
2. Move cursor to monitor 1 BEFORE the success state auto-resets.
3. Press hotkey to start a new dictation while cursor is on monitor 1.
4. **Expected:** New pill animation (recording phase) appears on monitor 1, NOT monitor 2.

**SC-3 (DISPLAY-02) — Disconnect monitor reposition:**
1. With the pill idle on monitor 2 (idle state — leave the app alone for ~5s after a dictation).
2. Disconnect monitor 2 (unplug HDMI/USB-C, or use Displays preference pane to disable).
3. **Expected:** Within ~1 second, the pill repositions onto monitor 1 (the remaining display). It should NOT be stranded off-screen.
4. Reconnect monitor 2 — pill stays on monitor 1 (no spurious jump unless cursor was already on the freshly-attached screen).

**SC-4 (visibleFrame respect) — Dock and notch:**
1. Configure one monitor with the Dock at the bottom and the other with the Dock on the left (System Settings → Desktop & Dock → "Show Dock on …").
2. Trigger dictation on each monitor (cursor on the screen first).
3. **Expected on each:** Pill sits ABOVE the bottom-anchored Dock (with ~4pt gap); on the left-Dock monitor, pill is horizontally centered in `visibleFrame` (which excludes the left Dock strip), so it shifts right of geometric center. Pill never overlaps Dock or menu bar/notch.

**SC-5 (cursor not on any screen — fallback) — Hotkey during display reconfiguration:**
This is rare and hard to reproduce deterministically. Best-effort:
1. Move cursor onto monitor 2.
2. Mid-hotkey-press (or just before pressing), unplug monitor 2 — cursor will briefly lose its screen during reconfiguration.
3. **Expected:** Pill appears on the remaining monitor (NSScreen.main fallback). No crash, no off-screen window.
   - **Acceptance:** if you can't reproduce the cursor-not-on-any-screen race, mark SC-5 as "fallback chain in code reads correct (verified in Task 1)" — the fallback is unit-of-thought level safety net, hard to trigger in normal use.

**Bonus (RESEARCH.md Pitfall 3 — debounce check):**
1. Pill is idle on monitor 2.
2. Open any unrelated app (Safari, Mail) and minimize it. Restore it. Minimize/restore 5 times rapidly.
3. **Expected:** Pill does NOT jump or visibly reposition on each minimize/restore. (Pre-debounce, it would jitter on macOS 14.)

**Bonus (correction popover):**
1. Dictate something into TextEdit on monitor 2.
2. Click the pill during the `.success` phase to open the correction popover.
3. **Expected:** Correction popover opens on monitor 2 (above where the pill was), NOT on monitor 1.
4. Press Esc or apply a correction.

---

Report: PASS or FAIL for each of SC-1 through SC-5 plus both bonuses. If any FAIL, paste Console.app output filtered by `[ListenToMe]` from the failure window.
  </how-to-verify>
  <resume-signal>Type "approved" if all 5 criteria pass (and at least one bonus passes), or describe failures with Console output.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| (none new) | This phase touches only window geometry and display enumeration. No new trust boundary is crossed. The existing app-process boundary, accessibility-permission boundary, and pasteboard boundary are unaffected. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-01 | Denial of Service | `displayConfigurationChanged` handler | mitigate | 100ms `Timer.scheduledTimer` debounce coalesces the macOS 14 minimize/restore notification storm (JDK-8353902) so a malicious or buggy app can't induce reposition-loop CPU burn by rapidly minimizing windows. |
| T-01-02 | Tampering | `NSEvent.mouseLocation` value used to choose screen | accept | The value is a read-only AppKit property reflecting actual cursor position; spoofing it requires CGEventTap-level access which already has higher privileges than this read. No PII exposed; worst case the pill lands on a different screen. |
| T-01-03 | Information Disclosure | Pill location reveals which screen the user is on | accept | The pill is already always-visible by design. Showing it on the active screen reveals only what was already implicitly observable. No data leak. |
| T-01-04 | Crash / Availability | `NSScreen.main` returns nil during display reconfiguration | mitigate | Triple-fallback chain `screens.first { contains } ?? .main ?? .screens.first ?? .screens[0]`. Final `[0]` is unreachable in practice but keeps signature non-optional for callers. |
</threat_model>

<verification>
## Phase Verification — ROADMAP Success Criteria → Manual Tests

| ROADMAP Criterion | Manual Test (in Task 4) | Pass Bar |
|-------------------|-------------------------|----------|
| 1. Cursor on monitor 2 → pill on monitor 2 | Task 4 SC-1 in TextEdit | Pill visibly anchors to monitor 2's bottom-center |
| 2. New dictation while cursor on monitor 2 → pill moves to monitor 2 | Task 4 SC-2 cross-monitor handoff | Pill on monitor 1 from prior dictation, new dictation on monitor 2 → pill follows |
| 3. Disconnect monitor with pill → pill repositions in ~1s | Task 4 SC-3 | Pill on remaining monitor within visible 1s window after disconnect |
| 4. Dock/menu-bar/notch respected on each screen (visibleFrame) | Task 4 SC-4 with Dock-position differences | Pill never overlaps Dock or menu bar/notch on any screen |
| 5. Falls back to NSScreen.main when cursor isn't over any screen | Task 4 SC-5 (or code review of fallback chain) | No crash; pill ends up on a connected screen |

## Code-level Invariants

After all tasks:

- `grep -v '^//' ListenToMe/UI/PillWindow.swift | grep -v '^ *//' | grep -c 'NSScreen.main'` returns 1 (only inside the `activeScreen()` fallback chain).
- `grep -v '^//' ListenToMe/UI/CorrectionWindow.swift | grep -v '^ *//' | grep -c 'NSScreen.main'` returns 0 (replaced by `activeScreen()` helper call).
- `grep -c 'positionAtTop' ListenToMe/UI/PillWindow.swift` returns 0 (renamed).
- Reposition call sits on the line directly before `state.phase = .recording` in `handlePress` (regex check in Task 2 verify).
- `./scripts/build.sh` succeeds end-to-end.
- App launches without crash and pill is visible immediately at startup (existing `showPersistent()` invariant preserved).
</verification>

<success_criteria>
1. `./scripts/build.sh` succeeds and produces a runnable `.app` showing version `0.7.0`.
2. The pill repositions to the screen containing the cursor at every dictation start (DISPLAY-01).
3. The pill repositions to a remaining monitor within ~1s of disconnecting the monitor it was on (DISPLAY-02).
4. The pill respects each screen's `visibleFrame` (no Dock/menu-bar/notch overlap) on multi-monitor setups with heterogeneous Dock positions.
5. Minimizing/restoring an unrelated window does NOT cause the pill to reposition (debounce verified).
6. `CorrectionWindow` opens on the same active screen as the pill it overlays.
7. All 5 ROADMAP Phase 1 success criteria PASS in Task 4 manual verification.
</success_criteria>

<out_of_scope>
Explicitly NOT in this phase (per CONTEXT.md Deferred Ideas):

- Continuous cursor tracking / mouse-move observer.
- Per-screen pill mirroring across all monitors.
- A Preferences toggle for active-screen behavior (not requested; behavior is unconditional).
- Live reposition of the `CorrectionWindow` while it's open (only repositions on `show()`; rare disconnect-while-open edge case accepted).
- Any change to pill appearance, animations, focus behavior, idle pulse, recording waveform, success halo, error shake, etc.
- Any change to `PillWindow.collectionBehavior`, `level`, or styling.
- AppDelegate refactors beyond a one-line insertion in `handlePress`.
</out_of_scope>

<output>
After completion, create `.planning/phases/01-multi-display-awareness/01-01-SUMMARY.md` documenting:
- What was built (active-screen resolution, debounced display-change observer, shared helper for both windows, version bump).
- Files modified with line-range deltas.
- Manual verification results from Task 4 (PASS/FAIL per success criterion).
- Any deviations from this plan (e.g., if `CorrectionWindow` had to be skipped for a discovered reason).
- Lessons learned / patterns established (e.g., debounce pattern for AppKit notifications under macOS 14 — reusable in future phases).
</output>
