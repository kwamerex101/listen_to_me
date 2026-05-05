# Phase 2: Selection-Aware Paste - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend `Paster` to query the macOS Accessibility API for the focused text element's selection state (range + text + line-above leading whitespace) immediately before pasting. Capture that state on `PasteToken` for downstream use. When the to-be-pasted text contains a `\n` (from the `new line` voice-edit token), inject the captured leading whitespace after each `\n` so the inserted line aligns with the original line's indent.

Out of scope: changing how pasting itself works (Cmd+V already replaces non-empty selection natively), surfacing the captured selection in the correction popover (recording only, behavioral changes deferred), AX-write replacement (rejected in REQUIREMENTS Out of Scope — Electron apps don't support it).

</domain>

<decisions>
## Implementation Decisions

### AX read failure handling

- **D-01:** Silent graceful degrade. If `AXUIElementCopyAttributeValue` fails for any reason — no AX access, app doesn't expose the attribute (Electron apps without proper text roles), focused element is nil — Paster sets `selectionRange = nil`, `selectedText = nil`, `leadingWhitespace = nil` on `PasteToken`. Paste proceeds exactly as today. No NSLog, no toast, no menu warning. Matches the existing fallback ethos (`claude` CLI missing → silent degrade; `kAXTrustedCheckOptionPrompt` denied → permission card).
- **D-02:** Do NOT try `kAXSelectedTextAttribute` (string only) as a backup. Without a range we can't restore selection, so the string-only fallback adds code without value. If it becomes useful in v2 (e.g. for the correction popover surface), revisit then.

### Indent semantics for `\n` from `new line` voice-edit

- **D-03:** Mirror leading whitespace exactly. Read the leading whitespace (`/^[ \t]*/`) of the line containing the AX cursor position at paste time. Inject that whitespace after each `\n` in the to-be-pasted text. Works in code editors, plain text, and markdown. No language detection.
- **D-04:** No "smart indent" (extra +tab after `{ [ ( :`). Smart-enter behavior is the receiving editor's job; mirroring is enough for the common case and we don't want to fight VS Code's own auto-indent.
- **D-05:** Indent injection happens in `Paster.pasteTracked` before writing to the pasteboard, NOT in `VoiceEditor.apply`. Rationale: at edit time we don't know the cursor's surrounding context yet; at paste time we do (AX has just been queried). `VoiceEditor` keeps emitting raw `\n`. `Paster` does the rewrite.

### Selection-state use (PASTE-03)

- **D-06:** Record only. Write `selectionRange`, `selectedText` to `PasteToken` for future use. Cmd+V already replaces non-empty selection natively, so paste behavior doesn't change in this phase. The recorded state becomes available for v2 features (auto-restore on replace failure, "restore original" button in correction popover).
- **D-07:** Do NOT use the recorded selection in `Paster.replace` failure paths (yet). Today, replace-fail leaves raw paste in target. Adding "restore the selection that was there before paste" is a behavioral change with edge cases (what if the replace succeeded for the cleanup phase but later correction-popover replace fails?) — defer to a separate v2 ticket.

### Claude's Discretion

- **Where the AX query lives.** Probably a new private method on `Paster` (e.g. `private static func captureSelectionState() -> SelectionState?`). Planner picks the cleanest seam.
- **Whether `PasteToken` gets new fields directly or wraps a sub-struct.** Either works; Swift `struct PasteToken { let selection: SelectionState? }` may read better than three new optionals on the existing struct.
- **Indent regex implementation.** `/^[ \t]*/` is sufficient. Whether to do it via `String.prefix(while:)`, `NSRegularExpression`, or hand-rolled char loop is a planner detail.
- **Reading the line above:** the AX cursor is at a `CFRange.location` within the focused element's value. The "line containing the cursor" is the substring from the previous `\n` to the next `\n` (or string boundaries). Planner can read `kAXValueAttribute` (full text), find that line, extract leading whitespace.
- **Multiline selection edge case.** If the user's selection at paste time spans multiple lines, what counts as the "leading whitespace of the line containing the cursor"? Use the line containing `selectionRange.location` (the start of the selection). Document this in PLAN.md.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Codebase
- `ListenToMe/Core/Paster.swift` — Primary file. Currently has `PasteToken` (simple struct), `pasteTracked`, `replace`, `finalize`, `paste` (legacy one-shot). All AX additions go here.
- `ListenToMe/Core/VoiceEditor.swift` — `applyParagraphBreaks` emits `\n` for "new line" voice tokens. Stays unchanged (D-05).
- `ListenToMe/ListenToMeApp.swift` — `handleRelease` calls `Paster.pasteTracked(expanded)` on line ~193. Insertion site for AX-aware paste.
- `ListenToMe/Core/HotkeyMonitor.swift` — Already requires AX trust (`AXIsProcessTrusted`). Phase 2's AX queries assume trust is granted; if not, the existing permission card is the user's path. Phase 2 adds no new permission UI.
- `.planning/codebase/ARCHITECTURE.md` — Pipeline overview.
- `.planning/codebase/CONVENTIONS.md` — Subprocess / @MainActor / typed-error patterns.
- `.planning/phases/01-multi-display-awareness/01-SUMMARY.md` — Phase 1 lesson on AppKit notification debounce; not directly relevant here but reference for AppKit subtlety patterns.

### macOS Accessibility APIs (developer.apple.com)
- `AXUIElementCreateSystemWide()` — entry point for system-wide AX queries.
- `AXUIElementCopyAttributeValue(_:_:_:)` — reads a single attribute. Returns `AXError`. Common errors: `.cannotComplete` (app not responding), `.attributeUnsupported` (Electron without text role), `.noValue` (selection is nil/empty), `.apiDisabled` (AX trust not granted — should be handled by the existing permission card before paste ever runs).
- `kAXFocusedUIElementAttribute` — the currently-focused UI element on the system.
- `kAXSelectedTextRangeAttribute` — `CFRange` of the selected text within the focused element. Empty selection → range with `length = 0`.
- `kAXSelectedTextAttribute` — the selected text as a string. Used only as a fallback we explicitly rejected (D-02).
- `kAXValueAttribute` — the full text content of the focused element. Used to find the line containing the cursor (D-05 line-above lookup).
- `AXValueGetValue(_:_:_:)` — extracts a `CFRange` from an `AXValue` opaque ref.

### Project planning
- `.planning/REQUIREMENTS.md` §Paste — PASTE-01, PASTE-02, PASTE-03 requirement text.
- `.planning/ROADMAP.md` Phase 2 — full success criteria (4 of them — re-read before planning).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Paster.PasteToken` struct already exists and is the natural place to add `selectionRange: CFRange?`, `selectedText: String?`, `leadingWhitespace: String?` (or a wrapping `SelectionState?`).
- `Paster.pasteTracked(_:)` is the only path that creates a `PasteToken`. Single insertion site for AX query.
- `Paster.replace` returns a fresh `PasteToken?` on success — that bookkeeping pattern continues; the new selection fields just propagate (or get re-queried; planner decides).
- `HotkeyMonitor.isAccessibilityGranted()` exists; AX trust is already a hard precondition for hotkey use, so AX queries from Paster have a near-100% chance of succeeding on a working installation.

### Established Patterns
- All AX reads happen on `@MainActor` (Paster is called from the main actor). No async needed.
- Optional return + nil-fallback is the codebase's idiom for "couldn't do it, move on" (e.g. `WhisperRunner.modelURL` lookup, `ClaudeClient.isAvailable`).
- Typed error enums (`WhisperError`, `ClaudeError`) — Phase 2 doesn't need a new error type because failures are silent. Optional return is sufficient.
- Module-internal (default) visibility for new helper functions — same as `activeScreen()` from Phase 1.

### Integration Points
- **AX query call site:** `Paster.pasteTracked(_:)` first line. Capture `SelectionState?` before the existing `let prior = pb.string(forType: .string)`.
- **Indent injection:** Right before `pb.setString(text, forType: .string)`. Replace `text` with `injectIndent(text, leadingWhitespace)` if `leadingWhitespace != nil`.
- **PasteToken propagation:** `Paster.replace` already mints fresh tokens on success. New fields get carried/refreshed there too.

### Known fragility
- AX queries on a non-responding app block until the system AX timeout (~5s). Mitigation: use `AXUIElementSetMessagingTimeout(element, 0.5)` to limit a single query to 500ms. Planner should bake this in.
- Some apps (notably TextEdit) expose `kAXSelectedTextRangeAttribute` but don't update it after Cmd+V — the recorded range is "before paste", which is exactly what we want for restoration. Confirms our timing choice (capture-then-paste, not paste-then-capture).

</code_context>

<specifics>
## Specific Ideas

- User flagged the desire for code-editor indent respect specifically — VS Code is the headline test case. The "indented Swift function body → 'new line' produces correctly indented continuation" success criterion in ROADMAP Phase 2 SC-3 traces to that.
- User dictates in Slack daily; PASTE-01's "graceful degrade in Electron" SC is non-negotiable for daily-life use.

</specifics>

<deferred>
## Deferred Ideas

- **Auto-restore on replace failure** — captured as the rejected option in question 3. Real value, but adds restore plumbing and edge cases. Belongs in v2 (CORR-* / QUAL-* category in REQUIREMENTS.md).
- **Selection visible in correction popover** — captured as the rejected option in question 3. Bigger UI change; belongs in v2.
- **AX-write replacement** — already in REQUIREMENTS.md Out of Scope (Electron apps don't support it; Cmd+Z+Cmd+V works everywhere we need it).
- **Smart indent (auto-add tab after { [ ( :)** — captured as the rejected option in question 2. Receiving editors handle this themselves.
- **`kAXSelectedTextAttribute` string-only fallback** — captured as the rejected option in question 1. No range = no restore value.

</deferred>

---

*Phase: 2-Selection-Aware-Paste*
*Context gathered: 2026-05-05*
