# Phase 2: Selection-Aware Paste — Research

**Researched:** 2026-05-05
**Domain:** macOS Accessibility API (ApplicationServices/HIServices), Swift CFTypeRef bridging, text manipulation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Silent graceful degrade on AX failure — set `selectionRange = nil`, `selectedText = nil`, `leadingWhitespace = nil` on `PasteToken`. No `NSLog`, no toast. Paste proceeds as today.
- **D-02:** No `kAXSelectedTextAttribute` string-only fallback. Without a range we can't restore selection; value-less fallback rejected.
- **D-03:** Indent = mirror leading whitespace `/^[ \t]*/` of cursor's line at paste time. No language detection.
- **D-04:** No smart indent (no extra +tab after `{ [ ( :`). Receiving editor handles that.
- **D-05:** Indent injection in `Paster.pasteTracked`, not in `VoiceEditor.apply`. VoiceEditor stays unchanged.
- **D-06:** Selection recording only — no behavioral change in this phase. Cmd+V already replaces non-empty selection natively.
- **D-07:** Do NOT use recorded selection in `Paster.replace` failure paths.

### Claude's Discretion
- Where the AX query lives — recommended: `private static func captureSelectionState() -> SelectionState?` on `Paster`.
- Whether `PasteToken` gets new fields directly or wraps a `SelectionState?` sub-struct.
- Indent regex implementation — `String.prefix(while:)` vs `NSRegularExpression` vs char loop.
- Line extraction detail — use `String.lineRange(for:)` to find the line containing the cursor.
- Multiline selection edge case: use the line containing `selectionRange.location` (start of selection).

### Deferred Ideas (OUT OF SCOPE)
- Auto-restore on replace failure
- Selection visible in correction popover
- AX-write replacement
- Smart indent (auto-add tab after `{ [ ( :`)
- `kAXSelectedTextAttribute` string-only fallback
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PASTE-01 | `Paster.pasteTracked` reads `kAXFocusedUIElementAttribute` and `kAXSelectedTextRangeAttribute` before pasting; captures selection state on `PasteToken` | AX API dance verified; Swift type bridging confirmed; graceful degrade pattern documented |
| PASTE-02 | When element supports AX text roles, Paster respects existing indentation when inserting `\n` from `new line` voice-edit token | `String.lineRange(for:)` approach verified; `replacingOccurrences(of: "\n", with: "\n" + ws)` confirmed; ordering vs. VoiceEditor.tidy verified safe |
| PASTE-03 | When AX reports non-empty selection at paste time, Paster records the original selected text in `PasteToken` for later correction use | Pattern: read `kAXSelectedTextRangeAttribute` → `kAXValueAttribute` substring; `length == 0` = empty selection; D-06 = record only, no behavior change |
</phase_requirements>

---

## Summary

Phase 2 adds two things to `Paster.pasteTracked`: (1) an AX read of the focused element's selection state immediately before pasting, stored on `PasteToken`; (2) leading-whitespace injection after each `\n` in the text being pasted, using the whitespace of the line the cursor sits on.

All AX APIs are available without additional permissions — `AXIsProcessTrusted()` grants both `CGEventTap` access (hotkey) and AX query access. The existing permission card is the user's path. The AX dance is four steps: `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` → per-element `AXUIElementSetMessagingTimeout(element, 0.5)` → `kAXSelectedTextRangeAttribute` + `kAXValueAttribute`. All calls happen synchronously on `@MainActor` before `simulatePasteKeystroke()`.

One scoping gap to flag: `Paster.replace()` receives the Claude-cleaned version of `expanded` (the pre-indent text), so when replace fires it will paste without the injected indent. This is acceptable for phase 2 (D-05 scopes injection to `pasteTracked` only) but should be noted as a known limitation for the planner to document.

**Primary recommendation:** Add a `private static func captureSelectionState() -> SelectionState?` on `Paster`; add a `struct SelectionState` sub-struct to keep `PasteToken` clean; call it as the first line of `pasteTracked`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| AX selection query | Core / Paster | — | Paster owns all pre-paste state capture; runs on @MainActor before Cmd+V |
| PasteToken data model | Core / Paster | — | PasteToken is internal to Paster module |
| Indent injection | Core / Paster | — | D-05 explicitly places this in pasteTracked, not VoiceEditor |
| AX trust precondition | Core / HotkeyMonitor | — | HotkeyMonitor already gates on AXIsProcessTrusted(); no new permission UI needed |
| VoiceEditor `\n` emission | Core / VoiceEditor | — | Stays unchanged (D-05); raw `\n` for "new line" voice token, no indent knowledge |

---

## Standard Stack

No new dependencies. All APIs are from `ApplicationServices` (already transitively imported via `AppKit`).

### Core APIs (all `[VERIFIED: macOS SDK headers]`)

| API | Header | Purpose |
|-----|--------|---------|
| `AXUIElementCreateSystemWide()` | `AXUIElement.h` | Entry point for system-wide AX queries |
| `AXUIElementCopyAttributeValue(_:_:_:)` | `AXUIElement.h` | Reads one attribute; returns `AXError`, value via `inout CFTypeRef?` |
| `AXUIElementSetMessagingTimeout(_:_:)` | `AXUIElement.h` | Per-element timeout in **seconds** (Float); `0` resets to global default |
| `AXValueGetValue(_:_:_:)` | `AXValue.h` | Extracts typed value from opaque `AXValue`; use `.cfRange` for `CFRange` |
| `kAXFocusedUIElementAttribute` | `AXAttributeConstants.h` | System-wide focused element |
| `kAXSelectedTextRangeAttribute` | `AXAttributeConstants.h` | `AXValueRef` of type `kAXValueTypeCFRange` (char range, not bytes) |
| `kAXValueAttribute` | `AXAttributeConstants.h` | Full text content of element; `CFString` bridged to `String` |

### Supporting (optional performance optimization, documented below)

| API | Purpose | Tradeoff |
|-----|---------|----------|
| `kAXLineForIndexParameterizedAttribute` | Get line number for char index (avoids reading full kAXValueAttribute) | Not universally supported (Electron may not expose it) |
| `kAXStringForRangeParameterizedAttribute` | Get substring for a CFRange (get just the current line) | Also not universal |
| `kAXNumberOfCharactersAttribute` | Read char count without reading full text | Useful if deciding whether to cap full-text reads |

**Recommendation:** Use `kAXValueAttribute` (full text) + `String.lineRange(for:)`. Simpler, universally supported. Performance concern addressed below.

---

## Architecture Patterns

### System Architecture Diagram

```
handleRelease (AppDelegate, @MainActor)
    └─> VoiceEditor.apply(raw)          ← emits raw "\n", trims whitespace per-line
        └─> SnippetsStore.expand(in:)
            └─> Paster.pasteTracked(expanded)
                    │
                    ├─> captureSelectionState()   ← NEW: AX query
                    │       AXUIElementCreateSystemWide()
                    │       ↓ kAXFocusedUIElementAttribute → AXUIElement
                    │       ↓ AXUIElementSetMessagingTimeout(element, 0.5)
                    │       ↓ kAXSelectedTextRangeAttribute → CFRange
                    │       ↓ kAXValueAttribute → String  (only if text contains "\n")
                    │       ↓ lineRange(for: cursorIdx) → leading whitespace
                    │       └─> SelectionState? (nil on any failure)
                    │
                    ├─> injectIndent(text, leadingWhitespace)  ← NEW: only if ws != nil && "\n" present
                    │
                    ├─> pb.setString(indentedText, forType: .string)
                    ├─> simulatePasteKeystroke()
                    └─> PasteToken(…, selection: selectionState)  ← NEW fields
```

### Recommended Project Structure

No new files required. All additions in `Paster.swift`:

```
ListenToMe/Core/Paster.swift
  struct SelectionState          ← NEW: selectionRange, selectedText, leadingWhitespace
  struct PasteToken              ← MODIFIED: add selection: SelectionState?
  enum Paster
    static func pasteTracked     ← MODIFIED: call captureSelectionState + injectIndent
    private static func captureSelectionState() -> SelectionState?   ← NEW
    private static func injectIndent(_:leadingWhitespace:) -> String  ← NEW
    private static func extractLeadingWhitespace(from:cursorLocation:) -> String  ← NEW
    … (existing methods unchanged)
```

### Pattern 1: AX Selection State Capture

**What:** Synchronous AX query sequence on @MainActor before pasteboard write.
**When to use:** First line of `pasteTracked`, before any pasteboard mutation.

```swift
// Source: verified against macOS SDK AXUIElement.h + AXValue.h headers (2026-05-05)
// Compiled and type-checked with `xcrun swift -e` on macOS 15 (Sequoia)
private static func captureSelectionState() -> SelectionState? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
    ) == .success, let focused = focusedRef else { return nil }

    let element = focused as! AXUIElement
    // Limit blocking to 0.5 s for this element (timeoutInSeconds is Float, units = seconds)
    AXUIElementSetMessagingTimeout(element, 0.5)

    // Read selection range
    var rangeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
    ) == .success, let axVal = rangeRef else { return nil }

    var cfRange = CFRange(location: 0, length: 0)
    guard AXValueGetValue(axVal as! AXValue, .cfRange, &cfRange) else { return nil }

    // Read full text only when the to-be-pasted text contains "\n" (caller decides;
    // alternatively always read it — see performance note below).
    var textRef: CFTypeRef?
    let fullText: String?
    if AXUIElementCopyAttributeValue(
        element, kAXValueAttribute as CFString, &textRef
    ) == .success, let s = textRef as? String {
        fullText = s
    } else {
        fullText = nil
    }

    // Extract selected text string if selection is non-empty
    let selectedText: String?
    if cfRange.length > 0, let text = fullText {
        let start = text.index(text.startIndex, offsetBy: cfRange.location,
                               limitedBy: text.endIndex) ?? text.endIndex
        let end   = text.index(start, offsetBy: cfRange.length,
                               limitedBy: text.endIndex) ?? text.endIndex
        selectedText = String(text[start..<end])
    } else {
        selectedText = nil
    }

    // Extract leading whitespace of line containing cursor (selectionRange.location)
    let leadingWhitespace: String?
    if let text = fullText {
        leadingWhitespace = extractLeadingWhitespace(from: text, cursorLocation: cfRange.location)
    } else {
        leadingWhitespace = nil
    }

    return SelectionState(
        selectionRange: cfRange,
        selectedText: selectedText,
        leadingWhitespace: leadingWhitespace
    )
}
```

### Pattern 2: Leading Whitespace Extraction

```swift
// Source: verified with xcrun swift -e; String.lineRange(for:) handles all edge cases
// Edge cases covered: cursor on first line, cursor at col 0, empty string, tabs
private static func extractLeadingWhitespace(from text: String, cursorLocation: Int) -> String {
    guard !text.isEmpty, cursorLocation >= 0 else { return "" }
    let loc = min(cursorLocation, text.count)
    let idx = text.index(text.startIndex, offsetBy: loc)
    let lineRange = text.lineRange(for: idx..<idx)
    let line = String(text[lineRange])
    return String(line.prefix(while: { $0 == " " || $0 == "\t" }))
}
```

### Pattern 3: Indent Injection

```swift
// Source: verified with xcrun swift -e; simple and correct for multiple \n
private static func injectIndent(_ text: String, leadingWhitespace ws: String) -> String {
    guard !ws.isEmpty, text.contains("\n") else { return text }
    return text.replacingOccurrences(of: "\n", with: "\n" + ws)
}
```

### Pattern 4: PasteToken + SelectionState model

```swift
struct SelectionState {
    /// CFRange of selected characters (not bytes) at paste time.
    /// length == 0 means insertion point (no selection).
    let selectionRange: CFRange
    /// The selected text substring. nil when length == 0 or kAXValueAttribute unavailable.
    let selectedText: String?
    /// Leading whitespace of the line containing selectionRange.location.
    /// nil when kAXValueAttribute unavailable or element has no text.
    let leadingWhitespace: String?
}

struct PasteToken {
    let bundleId: String?
    let changeCountAtPaste: Int
    let pastedText: String
    let priorPasteboardString: String?
    let timestamp: Date
    // NEW:
    let selection: SelectionState?   // nil when AX query failed or AX not available
}
```

### Anti-Patterns to Avoid

- **Force-unwrapping AXValue cast without guarding:** The `focusedRef as! AXUIElement` and `axVal as! AXValue` force casts are safe because `AXUIElementCopyAttributeValue` guarantees the CF type matches the attribute — but wrap them with `guard` or the outer `AXError == .success` gate so any unexpected `nil` falls through to `return nil`.
- **Reading `kAXValueAttribute` unconditionally every paste:** For long documents (10k+ chars), reading the full text is a synchronous AX call. Only read when the text to be pasted contains `\n` (i.e., `pasteText.contains("\n")`). This eliminates the cost on the common case (no voice "new line" tokens).
- **Setting global timeout instead of per-element:** `AXUIElementSetMessagingTimeout(systemWide, 0.5)` would affect all AX queries in the process. Always set it on the focused `element`, not on `systemWide`.
- **Querying AX after simulatePasteKeystroke:** AX state must be read before the keystroke so the focused element and selection reflect where the text will land.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Line boundary detection | Manual `\n`-scan loop | `String.lineRange(for:)` | Handles `\r\n`, `\r`, Unicode line separators, and edge cases (first/last line) correctly |
| CFRange ↔ Swift Range conversion | Index arithmetic | `text.index(startIndex, offsetBy: cfRange.location)` with `limitedBy:` guard | Prevents crash on out-of-bounds AX range (e.g., stale range after app mutated text) |
| AX type cast | Custom bridging | `as! AXUIElement`, `as! AXValue` with `AXError == .success` guard | CF_BRIDGED_TYPE; force cast is idiomatic and safe when guarded by success check |

---

## Common Pitfalls

### Pitfall 1: AX Timeout Unit Confusion
**What goes wrong:** Passing `500` instead of `0.5` to `AXUIElementSetMessagingTimeout`. The parameter is `Float timeoutInSeconds` (confirmed in SDK header: `AXUIElementSetMessagingTimeout(AXUIElementRef element, float timeoutInSeconds)`). Passing `500` sets a 500-second timeout — the app hangs on a non-responding target.
**Why it happens:** The name is explicit but the units are easy to confuse with milliseconds.
**How to avoid:** The parameter name is `timeoutInSeconds` in the header docs. Use `0.5` for a 500ms cap.
**Warning signs:** App hangs for a long time when dictating into a frozen/slow app.

### Pitfall 2: `kAXValueAttribute` on Large Documents
**What goes wrong:** `kAXValueAttribute` returns the entire text of the focused element. For a 50,000-word document, this is a large synchronous read. On a slow/unresponsive app it blocks `@MainActor` for up to `timeoutInSeconds`.
**Why it happens:** We only need one line's leading whitespace, but the API returns everything.
**How to avoid:** Only call `kAXValueAttribute` when `pastedText.contains("\n")` — skip it entirely on the common case. The 0.5s per-element timeout also bounds the worst case.
**Warning signs:** Noticeable pause before paste on long documents.

### Pitfall 3: Stale Selection Range (Out-of-Bounds Index)
**What goes wrong:** AX returns a `CFRange` that is valid at query time but the text changes between query and index operation. `text.index(startIndex, offsetBy: cfRange.location)` crashes if `cfRange.location > text.count`.
**Why it happens:** Race condition if another process or background thread mutated the text, or if `kAXValueAttribute` and `kAXSelectedTextRangeAttribute` are from different moments.
**How to avoid:** Always use `limitedBy: text.endIndex` on `index(_:offsetBy:limitedBy:)` and guard against nil.

### Pitfall 4: Setting Timeout on System-Wide Element
**What goes wrong:** `AXUIElementSetMessagingTimeout(systemWide, 0.5)` changes the global timeout for ALL AX queries in the process for the rest of the session (until reset with 0).
**Why it happens:** `AXUIElementSetMessagingTimeout` docs say passing the system-wide object sets the global timeout.
**How to avoid:** Call on the `element` (focused element), not `systemWide`.

### Pitfall 5: Indent Injection in `replace()` Path
**What goes wrong:** `Paster.replace(with: cleaned, token:)` receives the Claude-cleaned version of `expanded` — the pre-indentation text. If the original paste had `\n` with leading whitespace injected, the replacement will paste without that indent.
**Why it happens:** `startCleanupTask` passes `expanded` (not the indented version) to Claude.
**How to avoid:** This is accepted scope in phase 2 (D-05 scopes injection to `pasteTracked` only). Document as known limitation in PLAN.md. The fix (also indent-inject in `replace()`) is a phase 2.1 item.

### Pitfall 6: Electron / VS Code AX Support
**What goes wrong:** Some Electron apps (older versions) don't expose `kAXSelectedTextRangeAttribute`. `AXUIElementCopyAttributeValue` returns `.attributeUnsupported` (-25205) or `.noValue` (-25212).
**Why it happens:** Electron's AX bridge only partially exposes text roles depending on the version and whether the web content has the right ARIA roles.
**How to avoid:** The D-01 graceful degrade covers this — any non-`.success` return from any AX call causes `captureSelectionState()` to return `nil`, paste proceeds unchanged. VS Code AX exposure has improved in recent versions; Slack is the worst case.

---

## Code Examples

### Complete `captureSelectionState` call site in `pasteTracked`

```swift
// Source: integration site per CONTEXT.md § Integration Points
static func pasteTracked(_ text: String) -> PasteToken {
    // --- NEW: capture selection state before any pasteboard mutation ---
    let selectionState = captureSelectionState()
    // --- END NEW ---

    let pb = NSPasteboard.general
    let prior = pb.string(forType: .string)

    // --- NEW: inject indent if paste text has \n and we have leading whitespace ---
    let textToWrite: String
    if let ws = selectionState?.leadingWhitespace, text.contains("\n") {
        textToWrite = injectIndent(text, leadingWhitespace: ws)
    } else {
        textToWrite = text
    }
    // --- END NEW ---

    pb.clearContents()
    pb.setString(textToWrite, forType: .string)     // was: pb.setString(text, …)

    let changeCount = pb.changeCount
    let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

    simulatePasteKeystroke()

    return PasteToken(
        bundleId: bundleId,
        changeCountAtPaste: changeCount,
        pastedText: textToWrite,                    // store indented version
        priorPasteboardString: prior,
        timestamp: Date(),
        selection: selectionState                   // NEW field
    )
}
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| `AXUIElementRef` (ObjC name) | `AXUIElement` (Swift name, CF_BRIDGED_TYPE) | Renamed in Swift 3; force-cast `CFTypeRef as! AXUIElement` |
| `kAXValueCFRangeType` (legacy constant) | `AXValueType.cfRange` (Swift enum) / `kAXValueTypeCFRange` | Legacy `kAXValueCFRangeType` is still defined as alias; use the enum |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | VS Code (Electron) exposes `kAXSelectedTextRangeAttribute` in recent versions | Pitfall 6 | Low — D-01 graceful degrade handles failure; worst case: no indent in VS Code |
| A2 | `String.lineRange(for:)` handles `CFRange.location` measured in UTF-16 code units consistently with AX's character-index semantics | Pattern 2 | Medium — if AX uses UTF-16 offsets and Swift uses Unicode scalars, emoji/surrogate pairs could misalign. Mitigation: test with emoji in document. |
| A3 | `Paster` is always called from `@MainActor`; no async boundary needed for AX calls | Architecture Patterns | Low — confirmed by CONTEXT.md "All AX reads on @MainActor" |

---

## Open Questions

1. **AX character index semantics: UTF-16 vs Unicode scalar vs grapheme cluster?**
   - What we know: `kAXSelectedTextRangeAttribute` docs say "characters (not bytes)"; `String.lineRange` uses Swift's `String.Index` (grapheme clusters).
   - What's unclear: Does AX count emoji as 1 character or 2 (UTF-16 surrogate pair)?
   - Recommendation: Add a test case with an emoji in the document before the cursor. If misaligned, switch to `utf16.index(offsetBy:)` for the range lookup.

2. **Indent injection for `replace()` path?**
   - What we know: `replace()` gets Claude-cleaned text (same `\n`s, no indent). Indent injected in initial paste will be removed on replace.
   - What's unclear: Whether this is visually jarring enough to block shipping.
   - Recommendation: Accept as phase 2 known limitation. Document in PLAN.md. File a follow-up task.

3. **`SelectionState` read of `kAXValueAttribute` when text has no `\n`?**
   - Decision: Skip `kAXValueAttribute` when `pastedText.contains("\n")` is false. This means `leadingWhitespace` and `selectedText` (from text substring) are both nil in the no-`\n` case.
   - PASTE-03 requires recording selected text. If we skip `kAXValueAttribute` when no `\n`, we lose `selectedText` in the no-`\n` case.
   - Recommendation: Always read `kAXValueAttribute` (costs one AX call, bounded by 0.5s timeout), OR always read `kAXSelectedTextAttribute` for `selectedText` (but D-02 rejects that). Simplest: always read `kAXValueAttribute`, extract `selectedText` from it. Skip `leadingWhitespace` computation only when no `\n`.

---

## Environment Availability

Step 2.6: SKIPPED — phase is pure Swift code changes, no new external tools or CLI dependencies. All AX APIs are in the macOS SDK already linked via AppKit.

---

## Validation Architecture

No automated test framework configured (CLAUDE.md: "There are no automated tests; all testing is manual via the running app").

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| PASTE-01 | `pasteTracked` captures selection range in PasteToken | Manual | — | Dictate into TextEdit with selection; inspect via NSLog or breakpoint |
| PASTE-01 | Graceful degrade in Slack (Electron) | Manual | — | Dictate into Slack; confirm no crash, paste succeeds |
| PASTE-02 | `\n` from "new line" gets correct indent in VS Code | Manual | — | Open VS Code, cursor in indented function body, dictate "new line foo" |
| PASTE-02 | `\n` with no indent (first column) stays at column 0 | Manual | — | TextEdit with no indent, "new line" should not add whitespace |
| PASTE-03 | Non-empty selection recorded in PasteToken | Manual | — | Select "foo bar" in TextEdit, dictate; verify token.selection.selectedText == "foo bar" |

**SC-3 (ROADMAP):** VS Code, indented Swift function body, "new line" voice command → inserted line has matching indent. This is the headline test for PASTE-02.
**SC-4 (ROADMAP):** Slack dictation succeeds without crash. This is the headline test for D-01.

---

## Security Domain

No security-relevant surface changes. Phase adds read-only AX queries (no AX write, no new permissions, no network, no file I/O). `kAXValueAttribute` reads the focused element's text content — this data stays in-process and is used only for whitespace extraction. No storage, no logging (D-01).

---

## Sources

### Primary (HIGH confidence — verified against macOS SDK headers)
- `AXUIElement.h` (macOS 14 SDK, HIServices.framework) — `AXUIElementSetMessagingTimeout`, `AXUIElementCopyAttributeValue`, `AXUIElementCreateSystemWide` signatures and docs
- `AXValue.h` (macOS 14 SDK, HIServices.framework) — `AXValueGetValue`, `AXValueType.cfRange`
- `AXAttributeConstants.h` (macOS 14 SDK, HIServices.framework) — `kAXFocusedUIElementAttribute`, `kAXSelectedTextRangeAttribute`, `kAXValueAttribute` string values and semantics
- `AXError.h` (macOS 14 SDK, HIServices.framework) — `kAXErrorCannotComplete`, `kAXErrorAttributeUnsupported`, `kAXErrorNoValue`, `kAXErrorAPIDisabled`
- `xcrun swift -e` compilation — Swift type bridging patterns (`as! AXUIElement`, `as! AXValue`, `as? String`); `AXValueType.cfRange`; `String.lineRange(for:)`; `injectIndent` logic — all verified compile-clean

### Secondary (MEDIUM confidence)
- [Apple Developer Docs — AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) — parameter name `timeoutInSeconds` confirms seconds unit [CITED]
- [Swift Forums — AXValue to CFTypeRef bridging](https://forums.swift.org/t/error-converting-axvalue-to-cftyperef-in-axuielementcopyattributevalue-on-macos/65775) — community confirmation of `as! AXValue` pattern [CITED]

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — headers verified on macOS 14 SDK, function signatures confirmed via `xcrun`
- Architecture: HIGH — call site and ordering confirmed against actual `Paster.swift` and `ListenToMeApp.swift` source
- Pitfalls: HIGH (timeout units, stale range, global-vs-element timeout) / MEDIUM (Electron AX exposure, UTF-16 alignment)
- Code Examples: HIGH — all patterns compiled with `xcrun swift -e`

**Research date:** 2026-05-05
**Valid until:** 2026-11-05 (AX APIs are stable; AXValueType enum naming stable since Swift 3)
