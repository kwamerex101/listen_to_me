import AppKit
import ApplicationServices

/// Captured AX state of the focused text element at paste time.
/// All fields nil-tolerant so callers can degrade gracefully when the
/// AX tree doesn't expose what we need (e.g. Electron apps without
/// proper text roles).
struct SelectionState {
    /// CFRange of the selection within the focused element's value.
    /// `length == 0` means insertion-point-only (no selection).
    let selectionRange: CFRange
    /// The selected substring. nil when `selectionRange.length == 0` or
    /// when `kAXValueAttribute` was unavailable.
    let selectedText: String?
    /// Leading whitespace (`/^[ \t]*/`) of the line containing
    /// `selectionRange.location`. nil when `kAXValueAttribute` was
    /// unavailable. Empty string is a valid value (cursor at column 0
    /// of an unindented line) — distinguishes from "couldn't read".
    let leadingWhitespace: String?
}

/// Captures the state needed to safely replace a paste later, e.g. once
/// background cleanup finishes. The token is opaque to callers — they hand
/// it back to `Paster.replace(...)`.
struct PasteToken {
    let bundleId: String?
    /// Pasteboard `changeCount` immediately after we wrote our text.
    /// If something else writes to the pasteboard before we replace, this
    /// won't match — that's our "user did something" signal.
    let changeCountAtPaste: Int
    let pastedText: String
    /// Pasteboard string that was there before our paste. Restored after
    /// we're done replacing (or we hit max staleness).
    let priorPasteboardString: String?
    let timestamp: Date
    /// AX-captured selection state at paste time. nil when AX read failed
    /// for any reason (per D-01 graceful degrade). Recording-only for now;
    /// not consumed by `Paster.replace` failure paths (D-07).
    let selection: SelectionState?
}

/// Writes text to pasteboard, simulates Cmd+V into the active app, and
/// optionally lets a caller replace what was pasted later (used for the
/// "stream raw, polish in background" flow).
enum Paster {
    /// One-shot paste with auto-restore of the prior pasteboard contents
    /// after a short delay. Use when you do NOT plan to replace the text.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let prior = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        simulatePasteKeystroke()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let p = prior {
                pb.clearContents()
                pb.setString(p, forType: .string)
            }
        }
    }

    /// Paste-and-track. Returns a token that can be passed to `replace(...)`
    /// to swap in different text later. The pasteboard is NOT auto-restored —
    /// the caller must call `finalize(token:)` (or `replace(...)`, which
    /// finalizes implicitly) to put the user's prior clipboard back.
    static func pasteTracked(_ text: String) -> PasteToken {
        // Capture AX selection state BEFORE any pasteboard mutation. The
        // focused element and its selection must reflect where text will land.
        // Silent degrade on failure (D-01) — `selectionState` is nil.
        let selectionState = captureSelectionState()

        let pb = NSPasteboard.general
        let prior = pb.string(forType: .string)

        // Indent injection (D-03). Only when AX gave us non-empty whitespace
        // AND the to-be-pasted text contains \n (i.e., voice "new line" was
        // expanded by VoiceEditor). VoiceEditor stays unchanged per D-05.
        let textToWrite: String
        if let ws = selectionState?.leadingWhitespace, !ws.isEmpty, text.contains("\n") {
            textToWrite = injectIndent(text, leadingWhitespace: ws)
        } else {
            textToWrite = text
        }

        pb.clearContents()
        pb.setString(textToWrite, forType: .string)

        // Capture changeCount AFTER our write so we can detect later
        // pasteboard mutations by anything that isn't us.
        let changeCount = pb.changeCount
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        simulatePasteKeystroke()

        return PasteToken(
            bundleId: bundleId,
            changeCountAtPaste: changeCount,
            pastedText: textToWrite,           // store the indented version
            priorPasteboardString: prior,
            timestamp: Date(),
            selection: selectionState
        )
    }

    /// Attempts to replace previously-pasted text with `newText`, by
    /// simulating Cmd+Z (to undo the original paste) then Cmd+V with the
    /// new text. Returns a fresh `PasteToken` pointing at the new paste
    /// on success, `nil` if any validation check fails (the original
    /// paste stands in that case).
    @discardableResult
    static func replace(with newText: String,
                        token: PasteToken,
                        maxStaleness: TimeInterval = 30) -> PasteToken? {
        // Bail early if the text is identical — nothing to do, but also
        // don't trigger an undo+repaste flicker. Return a refreshed token
        // so caller bookkeeping stays sensible.
        if newText == token.pastedText {
            finalize(token: token)
            return PasteToken(
                bundleId: token.bundleId,
                changeCountAtPaste: NSPasteboard.general.changeCount,
                pastedText: newText,
                priorPasteboardString: token.priorPasteboardString,
                timestamp: Date(),
                selection: token.selection
            )
        }

        // Gate 1: staleness. If too much time has passed, the user has
        // likely moved on; don't risk clobbering their work.
        if Date().timeIntervalSince(token.timestamp) > maxStaleness {
            finalize(token: token)
            return nil
        }

        // Gate 2: same frontmost app. If they've switched, don't replace.
        let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if currentBundle != token.bundleId {
            finalize(token: token)
            return nil
        }

        // Gate 3: pasteboard untouched. Anyone else (the user, another app)
        // writing to the pasteboard would have bumped the changeCount.
        let pb = NSPasteboard.general
        if pb.changeCount != token.changeCountAtPaste {
            finalize(token: token)
            return nil
        }

        // Validation passed — perform the swap.
        simulateUndoKeystroke()
        // Give the target app a moment to apply the undo before we paste.
        // 80ms is roomy enough for Electron apps without feeling laggy.
        usleep(80_000)

        // Re-apply indent injection on the replacement text using the
        // leadingWhitespace captured at original paste time (Phase 2.1
        // fix to D-05 boundary). Without this, Claude cleanup re-pastes
        // un-indented text into a code editor and the SC-3 indent benefit
        // is lost ~10s after the user dictates.
        let textToWrite: String
        if let ws = token.selection?.leadingWhitespace, !ws.isEmpty, newText.contains("\n") {
            textToWrite = injectIndent(newText, leadingWhitespace: ws)
        } else {
            textToWrite = newText
        }

        pb.clearContents()
        pb.setString(textToWrite, forType: .string)
        let newChangeCount = pb.changeCount
        simulatePasteKeystroke()

        // Restore the user's original pasteboard a beat after our paste
        // settles. 0.6s matches the existing fire-and-forget paste path.
        let prior = token.priorPasteboardString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let p = prior {
                pb.clearContents()
                pb.setString(p, forType: .string)
            }
        }

        return PasteToken(
            bundleId: token.bundleId,
            changeCountAtPaste: newChangeCount,
            pastedText: textToWrite,
            priorPasteboardString: token.priorPasteboardString,
            timestamp: Date(),
            selection: token.selection
        )
    }

    /// Restore the prior pasteboard string captured at paste time. Call
    /// this when you've decided NOT to replace (e.g. cleanup threw).
    static func finalize(token: PasteToken) {
        let pb = NSPasteboard.general
        // Only restore if the pasteboard hasn't been touched since our
        // paste — otherwise we'd overwrite something the user just copied.
        if pb.changeCount == token.changeCountAtPaste,
           let prior = token.priorPasteboardString {
            pb.clearContents()
            pb.setString(prior, forType: .string)
        }
    }

    // MARK: - AX Selection Capture

    /// Reads selection range, selected text, and leading whitespace of the
    /// cursor's line from the system-wide focused element. Returns nil on
    /// any AX failure (per D-01 graceful degrade — no NSLog, no UI).
    ///
    /// Always reads `kAXValueAttribute` (one extra AX call) so `selectedText`
    /// is populated even when the to-be-pasted text has no `\n`. Per RESEARCH
    /// open-question 3.
    private static func captureSelectionState() -> SelectionState? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef = focusedRef else { return nil }

        let element = focusedRef as! AXUIElement
        // 0.5 SECONDS — parameter is `timeoutInSeconds: Float`. NOT milliseconds.
        // Set on `element`, NOT `systemWide` (would set process-wide global).
        AXUIElementSetMessagingTimeout(element, 0.5)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success, let rangeRef = rangeRef else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }

        // Read full text. Bounded by the 0.5s per-element timeout above.
        var textRef: CFTypeRef?
        let fullText: String?
        if AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &textRef
        ) == .success, let s = textRef as? String {
            fullText = s
        } else {
            fullText = nil
        }

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

        let leadingWhitespace: String?
        if let text = fullText {
            leadingWhitespace = extractLeadingWhitespace(from: text,
                                                         cursorLocation: cfRange.location)
        } else {
            leadingWhitespace = nil
        }

        return SelectionState(
            selectionRange: cfRange,
            selectedText: selectedText,
            leadingWhitespace: leadingWhitespace
        )
    }

    /// Returns the leading whitespace (`/^[ \t]*/`) of the line containing
    /// `cursorLocation` within `text`. Per D-03 mirror semantics. Per
    /// CONTEXT.md multi-line selection note: cursor = `selectionRange.location`,
    /// the START of the selection.
    private static func extractLeadingWhitespace(from text: String,
                                                  cursorLocation: Int) -> String {
        guard !text.isEmpty, cursorLocation >= 0 else { return "" }
        let loc = min(cursorLocation, text.count)
        let idx = text.index(text.startIndex, offsetBy: loc,
                              limitedBy: text.endIndex) ?? text.endIndex
        let lineRange = text.lineRange(for: idx..<idx)
        let line = text[lineRange]
        return String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    /// Inserts `ws` after every `\n` in `text`. No-op when `ws` is empty or
    /// `text` contains no `\n`. Per D-03 (mirror only — no smart indent per D-04).
    private static func injectIndent(_ text: String, leadingWhitespace ws: String) -> String {
        guard !ws.isEmpty, text.contains("\n") else { return text }
        return text.replacingOccurrences(of: "\n", with: "\n" + ws)
    }

    // MARK: - Keystroke Simulation

    private static func simulatePasteKeystroke() {
        postCmdKey(virtualKey: 9) // V
    }

    private static func simulateUndoKeystroke() {
        postCmdKey(virtualKey: 6) // Z
    }

    private static func postCmdKey(virtualKey: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }
}
