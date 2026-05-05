import AppKit

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
        let pb = NSPasteboard.general
        let prior = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        // Capture changeCount AFTER our write so we can detect later
        // pasteboard mutations by anything that isn't us.
        let changeCount = pb.changeCount
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        simulatePasteKeystroke()

        return PasteToken(
            bundleId: bundleId,
            changeCountAtPaste: changeCount,
            pastedText: text,
            priorPasteboardString: prior,
            timestamp: Date()
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
                timestamp: Date()
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

        pb.clearContents()
        pb.setString(newText, forType: .string)
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
            pastedText: newText,
            priorPasteboardString: token.priorPasteboardString,
            timestamp: Date()
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
