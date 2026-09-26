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
    /// Full pasteboard contents (every item, every type) that were there
    /// before our paste. Restored automatically a beat after the paste, and
    /// again after we're done replacing (or we hit max staleness).
    let priorPasteboard: PasteboardSnapshot
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
    /// changeCount right after our own restore, keyed by the token's
    /// `changeCountAtPaste` that the restore was for. Lets `replace` tell
    /// "we restored the user's clipboard" apart from "the user copied
    /// something" (Gate 3 would otherwise treat our own restore as a
    /// pasteboard change and refuse to replace). Bounded: only the most
    /// recent ~8 entries are kept, since a stale token is unusable anyway.
    private static var restoredChangeCounts: [Int: Int] = [:]
    /// Insertion order of `restoredChangeCounts` keys, oldest first. Tracked
    /// separately from the dictionary itself because eviction needs "oldest
    /// recorded", not "smallest key": changeCount is monotonic in practice,
    /// but nothing guarantees it, so sorting by key value isn't reliable.
    private static var restoredChangeCountOrder: [Int] = []

    /// Records that `pasteChangeCount` (a token's `changeCountAtPaste`) was
    /// followed by an automatic restore that left the pasteboard at
    /// `restoredChangeCount`. `internal` so tests can call it directly.
    static func recordRestore(pasteChangeCount: Int, restoredChangeCount: Int) {
        if restoredChangeCounts[pasteChangeCount] == nil {
            restoredChangeCountOrder.append(pasteChangeCount)
        }
        restoredChangeCounts[pasteChangeCount] = restoredChangeCount
        while restoredChangeCountOrder.count > 8 {
            let oldest = restoredChangeCountOrder.removeFirst()
            restoredChangeCounts.removeValue(forKey: oldest)
        }
    }

    /// True when the pasteboard is still in the state `replace`/`finalize`
    /// expect: either untouched since the token's paste, or touched only by
    /// our own automatic restore of that paste. `internal` so tests can call
    /// it directly.
    static func pasteboardUntouched(since token: PasteToken, currentChangeCount: Int) -> Bool {
        currentChangeCount == token.changeCountAtPaste
            || currentChangeCount == restoredChangeCounts[token.changeCountAtPaste]
    }

    /// One-shot paste with auto-restore of the prior pasteboard contents
    /// after a short delay. Use when you do NOT plan to replace the text.
    ///
    /// The restore is gated by changeCount: if anything (the user's own
    /// Cmd+C, another app, anything) wrote to the pasteboard between our
    /// paste and the 600ms restore tick, we leave it alone. Without the
    /// gate we'd clobber whatever the user just copied.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let changeCountAtPaste = pb.changeCount

        simulatePasteKeystroke()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pb.changeCount == changeCountAtPaste else { return }
            snapshot.restore(to: pb)
            recordRestore(pasteChangeCount: changeCountAtPaste, restoredChangeCount: pb.changeCount)
        }
    }

    /// Paste-and-track. Returns a token that can be passed to `replace(...)`
    /// to swap in different text later. The pasteboard IS auto-restored a
    /// beat after the paste (same as `paste(_:)`); `replace`/`finalize` still
    /// work afterwards because `pasteboardUntouched` recognizes our own
    /// restore, not just an untouched pasteboard.
    static func pasteTracked(_ text: String) -> PasteToken {
        // Capture AX selection state BEFORE any pasteboard mutation. The
        // focused element and its selection must reflect where text will land.
        // Silent degrade on failure (D-01) — `selectionState` is nil.
        let selectionState = captureSelectionState()

        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pb)

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

        // Auto-restore the user's prior clipboard a beat after the paste
        // settles, same delay as the one-shot `paste(_:)`. Gated on
        // changeCount so a copy the user made in that window is never
        // clobbered; `recordRestore` lets `replace`/`finalize` still work
        // afterwards even though our restore itself bumps changeCount.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pb.changeCount == changeCount else { return }
            snapshot.restore(to: pb)
            recordRestore(pasteChangeCount: changeCount, restoredChangeCount: pb.changeCount)
        }

        return PasteToken(
            bundleId: bundleId,
            changeCountAtPaste: changeCount,
            pastedText: textToWrite,           // store the indented version
            priorPasteboard: snapshot,
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
        // Secure-input guard. If a password field now has focus, never paste
        // into it. Returning nil composes with the pipeline's pre-paste guard:
        // the backtrack caller falls through to the normal dictation path,
        // which is itself blocked + reported by the SecureInput gate.
        if SecureInput.isActive {
            finalize(token: token)
            return nil
        }

        // Bail early if the text is identical — nothing to do, but also
        // don't trigger an undo+repaste flicker. Return a refreshed token
        // so caller bookkeeping stays sensible.
        if newText == token.pastedText {
            finalize(token: token)
            return PasteToken(
                bundleId: token.bundleId,
                changeCountAtPaste: NSPasteboard.general.changeCount,
                pastedText: newText,
                priorPasteboard: token.priorPasteboard,
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
        // writing to the pasteboard would have bumped the changeCount, but
        // our own automatic restore (pasteTracked's +0.6s tick) also bumps
        // it, so `pasteboardUntouched` recognizes that case too instead of
        // treating it as "the user copied something".
        let pb = NSPasteboard.general
        if !pasteboardUntouched(since: token, currentChangeCount: pb.changeCount) {
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
        // changeCount-gated: if the user (or another app) wrote to the
        // pasteboard during this window, leave it alone (clobbering a
        // fresh copy would be a worse bug than not restoring).
        let snapshot = token.priorPasteboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pb.changeCount == newChangeCount else { return }
            snapshot.restore(to: pb)
            recordRestore(pasteChangeCount: newChangeCount, restoredChangeCount: pb.changeCount)
        }

        return PasteToken(
            bundleId: token.bundleId,
            changeCountAtPaste: newChangeCount,
            pastedText: textToWrite,
            priorPasteboard: snapshot,
            timestamp: Date(),
            selection: token.selection
        )
    }

    /// Restore the prior pasteboard captured at paste time. Call this when
    /// you've decided NOT to replace (e.g. cleanup threw). A no-op once the
    /// automatic restore (from `pasteTracked`/`replace`) has already run,
    /// which is fine; it's still needed for early-return paths that finalize
    /// before that 0.6s tick fires.
    static func finalize(token: PasteToken) {
        let pb = NSPasteboard.general
        // Only restore if the pasteboard hasn't been touched since our
        // paste — otherwise we'd overwrite something the user just copied.
        if pb.changeCount == token.changeCountAtPaste {
            token.priorPasteboard.restore(to: pb)
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

    /// Inserts `ws` at the start of every non-empty continuation line.
    /// No-op when `ws` is empty or `text` contains no `\n`. Blank lines
    /// (paragraph breaks from pause detection) stay blank — indenting
    /// them would turn "\n\n" into "\n<ws>\n<ws>" and leave trailing
    /// whitespace inside the break. Per D-03 (mirror only — no smart
    /// indent per D-04). Internal (not private) so tests can exercise
    /// the blank-line rule directly — same pattern as
    /// `PartialTranscriber.isSilent` / `WhisperLib.joinSegments`.
    static func injectIndent(_ text: String, leadingWhitespace ws: String) -> String {
        guard !ws.isEmpty, text.contains("\n") else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { i, line in (i == 0 || line.isEmpty) ? String(line) : ws + line }
            .joined(separator: "\n")
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
