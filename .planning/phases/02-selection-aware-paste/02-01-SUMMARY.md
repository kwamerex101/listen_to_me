---
phase: 02-selection-aware-paste
plan: "01"
subsystem: Core/Paster
tags: [ax-api, selection, indent, paste, version-bump]
dependency_graph:
  requires: []
  provides: [SelectionState, PasteToken.selection, captureSelectionState, injectIndent]
  affects: [ListenToMe/Core/Paster.swift, project.yml, ListenToMe/Info.plist, SUPPORT.md]
tech_stack:
  added: [ApplicationServices (AX API)]
  patterns: [silent-degrade, AX-per-element-timeout, indent-mirror]
key_files:
  created: []
  modified:
    - ListenToMe/Core/Paster.swift
    - project.yml
    - ListenToMe/Info.plist
    - SUPPORT.md
decisions:
  - "D-01: Silent degrade — AX failures return nil SelectionState with no NSLog or UI"
  - "D-02: No kAXSelectedTextAttribute fallback — range+value only"
  - "D-03: Mirror leading whitespace after each \\n — no smart indent"
  - "D-04: No context-aware smart indent deferred"
  - "D-05: VoiceEditor.swift unchanged — indent injection in pasteTracked only"
  - "D-06: SelectionState on PasteToken is recording-only — replace() ignores it"
  - "D-07: replace() constructs PasteToken with selection: nil"
metrics:
  duration: "~20min"
  completed: "2026-05-05"
  tasks_completed: 2
  tasks_total: 3
  files_modified: 4
---

# Phase 02 Plan 01: Selection-Aware Paste Summary

JWT-style: AX selection capture + indent mirror wired into `Paster.pasteTracked` with silent degrade on failure.

## What Was Built

### Task 1: SelectionState, AX helpers, PasteToken field, pasteTracked wiring

Added to `ListenToMe/Core/Paster.swift`:

- **`SelectionState` struct** — captures `selectionRange: CFRange`, `selectedText: String?`, `leadingWhitespace: String?` from the focused AX element at paste time
- **`PasteToken.selection: SelectionState?`** — new field; nil when AX read fails or in replace() paths (D-07)
- **`captureSelectionState() -> SelectionState?`** — reads `kAXFocusedUIElementAttribute`, `kAXSelectedTextRangeAttribute`, `kAXValueAttribute` with a 0.5s per-element timeout; returns nil on any AX failure (D-01)
- **`extractLeadingWhitespace(from:cursorLocation:)`** — uses `String.lineRange(for:)` to find cursor's line, then `prefix(while:)` for spaces/tabs
- **`injectIndent(_:leadingWhitespace:)`** — replaces `\n` with `\n + ws`; no-op when ws empty or text has no `\n`
- **`pasteTracked`** — calls `captureSelectionState()` first (before any pasteboard mutation), applies `injectIndent` conditionally, stores indented text in `pastedText`, attaches `selectionState` to returned token
- **`replace()`** — both `PasteToken` constructions pass `selection: nil` (D-07)

`import ApplicationServices` added alongside `import AppKit`.

### Task 2: Version bump 0.7.0 → 0.8.0

- `project.yml`: `CFBundleShortVersionString` 0.7.0 → 0.8.0, `CFBundleVersion` 7 → 8
- `ListenToMe/Info.plist`: same fields updated
- `SUPPORT.md`: "Known limitations in v0.7.0" → "v0.8.0"
- `xcodegen generate` run to sync xcodeproj

## Task 3: Checkpoint (Awaiting Human Verification)

Manual multi-app testing required. See checkpoint signal below.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all data paths wired. `SelectionState` is populated from AX (or nil on failure); indent injection is live.

## Known Limitations

1. **`Paster.replace()` indent loss** — When Claude cleanup fires, the replacement text is the pre-indent Claude output; `replace()` does not re-inject indent. Accepted per D-05 (indent injection in `pasteTracked` only). Phase 2.1 follow-up: inject indent in `replace()` path too.

2. **UTF-16 vs grapheme cluster alignment** — `kAXSelectedTextRangeAttribute` returns `CFRange` in characters; Swift `String.index(_:offsetBy:)` operates on grapheme clusters. Emoji/surrogate pairs before cursor may misalign by 1. Guarded with `limitedBy: text.endIndex` — won't crash, may extract wrong `leadingWhitespace` on emoji-heavy docs. Deferred until empirical evidence.

3. **`replace()` does not restore selection** — D-07 explicitly defers this. `PasteToken.selection` is bookkeeping only in Phase 2.

## Phase 2.1 Follow-Up Candidates

- Inject indent in `Paster.replace()` path (currently drops indent on Claude cleanup replace)
- Selection restore on replace failure (D-07 deferred)
- UTF-16-safe index arithmetic for emoji edge case

## Threat Flags

None — threat register T-02-01 through T-02-04 all addressed in implementation:
- T-02-01 (info disclosure): data stays in-process, no logging of AX state (D-01)
- T-02-02 (DoS): `AXUIElementSetMessagingTimeout(element, 0.5)` on element (not systemWide)
- T-02-03 (tampering/OOB): all `String.index(_:offsetBy:limitedBy:)` guarded with `?? endIndex`
- T-02-04 (info disclosure via logging): `! grep NSLog.*selection` passes

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | `74ce92a` | feat(02-01): add SelectionState, AX capture helpers, and indent injection to Paster |
| Task 2 | `368b392` | chore(02-01): bump version 0.7.0 → 0.8.0 (build 7 → 8) |

## Verification

**VERIFIED ✓** — User completed manual smoke tests on 2026-05-05 across TextEdit, VS Code (Cleanup Mode = Never), and Slack. All four ROADMAP Phase 2 success criteria (SC-1..SC-4) confirmed working — including the headline VS Code indent test (SC-3). PR #11 merged to main (commit `89120a9`).

Phase 2.1 follow-up (indent through cleanup→replace) lands as a separate small PR before Phase 3 begins, closing the D-05 boundary so auto-learning-dictionary work doesn't compound the indent regression.

## Self-Check: PASSED

- `ListenToMe/Core/Paster.swift`: modified with all required symbols
- `project.yml`: shows 0.8.0
- `ListenToMe/Info.plist`: shows 0.8.0
- `SUPPORT.md`: shows v0.8.0
- Build: `BUILD SUCCEEDED` (xcodebuild Debug)
- VoiceEditor.swift: byte-identical to baseline (D-05)
- D-01/D-02: verified via grep (`! kAXSelectedTextAttribute`, `! NSLog.*selection|AX`)
- Commits `74ce92a` and `368b392` exist in git log
