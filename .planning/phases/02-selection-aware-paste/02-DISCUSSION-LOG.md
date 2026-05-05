# Phase 2: Selection-Aware Paste - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 2-selection-aware-paste
**Areas discussed:** AX failure handling, Indent semantics, Selection-state use

---

## AX failure handling

| Option | Description | Selected |
|--------|-------------|----------|
| Silent graceful degrade | Treat as no selection captured. Token fields nil, paste behaves as today. Matches existing fallback ethos. | ✓ |
| Try kAXSelectedTextAttribute as backup | Fallback to string-only AX attribute. More code, marginal benefit since no range = no restore. | |
| Log to NSLog when AX read fails | Same silent degrade behavior + diagnostic logging for future debugging. | |

**User's choice:** Silent graceful degrade (Recommended)
**Notes:** None.

---

## Indent semantics for `\n`

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror leading whitespace | Copy `/^[ \t]*/` of cursor's line and inject after each `\n`. Predictable, no language detection. | ✓ |
| Smart indent | Mirror + extra indent after `{ [ ( :`. More code, language-agnostic but occasionally wrong. | |
| No indent handling — raw `\n` | Don't touch indentation. Smaller scope, doesn't fully satisfy PASTE-02. | |

**User's choice:** Mirror leading whitespace (Recommended)
**Notes:** None.

---

## Selection-state use (PASTE-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Just record — no behavioral change | Record selectionRange and selectedText for future use. No paste behavior change. | ✓ |
| Auto-restore on replace failure | Push recorded text back to pasteboard if Paster.replace fails its gates. | |
| Surface in correction popover | Show recorded selection as "original text" with restore button. Bigger UI change, v2. | |

**User's choice:** Just record — no behavioral change yet (Recommended)
**Notes:** None.

---

## Claude's Discretion

- Where exactly the AX query lives (private method vs free function).
- Whether `PasteToken` gets new fields directly or wraps a sub-struct.
- Indent regex / extraction implementation (regex vs prefix-while vs hand-rolled).
- Indent extraction method for line above (read kAXValueAttribute and slice, vs other approaches).
- Multiline-selection edge case (use line containing `selectionRange.location`).

## Deferred Ideas

- Auto-restore on replace failure — value-real, but edge cases need their own ticket. v2 CORR/QUAL.
- Selection visible in correction popover — bigger UI work, v2.
- AX-write replacement — already explicitly Out of Scope (Electron incompatibility).
- Smart indent — receiving editors do this themselves.
- kAXSelectedTextAttribute string-only fallback — no range = no value.
