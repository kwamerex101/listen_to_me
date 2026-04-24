import AppKit

/// Writes text to pasteboard and simulates Cmd+V into the active app.
/// Restores prior pasteboard contents shortly after.
enum Paster {
    static func paste(_ text: String) {
        let pb = NSPasteboard.general

        // Snapshot current contents (best-effort: we only preserve strings)
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

    private static func simulatePasteKeystroke() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9   // V

        if let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }
}
