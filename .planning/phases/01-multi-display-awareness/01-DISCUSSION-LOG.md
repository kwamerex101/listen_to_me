# Phase 1: Multi-Display Awareness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 1-multi-display-awareness
**Areas discussed:** Active screen definition, Reposition cadence, Idle pill behavior

---

## Active screen definition

| Option | Description | Selected |
|--------|-------------|----------|
| Cursor location | `NSEvent.mouseLocation`. Simple, snappy, matches "the screen I'm physically pointing at". Falls back to `NSScreen.main` if cursor is nowhere. | ✓ |
| Frontmost app's main window | Use the screen containing the frontmost app's main window. More semantic but unreliable for windowless apps and slower (needs AX). | |
| Cursor first, frontmost-app fallback | Best-of-both: cursor primary, frontmost-app secondary on edge cases. More code, marginal benefit. | |

**User's choice:** Cursor location (Recommended)
**Notes:** None — accepted recommendation.

---

## Reposition cadence

| Option | Description | Selected |
|--------|-------------|----------|
| Only when becoming visible | Reposition when entering a non-idle phase + on display-config change. Lowest CPU, predictable. | ✓ |
| Continuously while idle too | Even the tiny idle dot tracks the cursor. Most "alive" feel but adds an event observer firing on every cursor cross-screen. | |
| On every phase change | Reposition on any phase transition (including back to idle). Subtle middle ground. | |

**User's choice:** Only when becoming visible (Recommended)
**Notes:** None.

---

## Idle visibility

| Option | Description | Selected |
|--------|-------------|----------|
| One pill on the active screen | Single instance, follows the cursor rule. Matches today's mental model. | ✓ |
| Mirrored on every connected screen | A pill instance on each connected display. Always present everywhere. More NSPanel instances and state to sync. | |

**User's choice:** One pill on the active screen (Recommended)
**Notes:** None.

---

## Claude's Discretion

- Exact insertion point for the reposition call (handlePress vs phase-change observer).
- Whether `CorrectionWindow` gets the same active-screen logic in this phase or stays a follow-on ticket.
- Renaming `positionAtTop()` for clarity (it actually anchors at the bottom).
- Observer lifecycle for `didChangeScreenParametersNotification`.

## Deferred Ideas

- Continuous cursor tracking — could be added as a preference later if per-press repositioning proves insufficient.
- Mirrored pill across all screens — out of scope; rejected by user.
- `CorrectionWindow` active-screen logic — folded in if trivial, else follow-on.
- Renaming `positionAtTop` — minor cleanup ride-along, not its own phase.
