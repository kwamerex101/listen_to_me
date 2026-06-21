import Foundation

/// Writes dictations into Apple Notes via AppleScript. The pure helpers
/// (HTML escaping, title derivation, script generation) are testable; the
/// bounded executor `write(text:)` (added separately) talks to Notes.app and
/// is gated so it only runs when the user selected an Apple Notes destination.
///
/// TCC: sending these Apple Events triggers the one-time "ListenToMe wants to
/// control Notes" Automation prompt. We never run the executor on launch.
enum NotesWriter {

    // MARK: - Pure helpers (unit-tested)

    /// Minimal HTML escape for Notes bodies (Notes stores rich-text HTML).
    /// Newlines become <br> so multi-line dictations keep their line breaks.
    static func escapeHTML(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "\n", with: "<br>")
        return out
    }

    /// One timestamped paragraph, mirroring the daily-note bullet format
    /// (`- **HH:mm** — text`) but as Notes HTML.
    static func bodyParagraph(timestamp: String, text: String) -> String {
        "<div><b>\(escapeHTML(timestamp))</b>&nbsp;\(escapeHTML(text))</div>"
    }

    /// Title for the target note given the mode.
    /// - dailyNote → the date string.
    /// - appendToDefault → the configured default title.
    /// - newEachTime → first six words of the dictation, or the date if empty.
    static func noteTitle(mode: NoteMode, defaultTitle: String,
                          text: String, dateString: String) -> String {
        switch mode {
        case .dailyNote:
            return dateString
        case .appendToDefault:
            return defaultTitle
        case .newEachTime:
            let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(6)
            let joined = words.joined(separator: " ")
            return joined.isEmpty ? dateString : joined
        }
    }

    /// Escape a Swift string for embedding inside an AppleScript double-quoted
    /// literal: backslash first, then double-quote.
    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// AppleScript that ensures `folder` exists, then makes a new note with
    /// `title` + `bodyHTML` inside it.
    static func createScript(folder: String, title: String, bodyHTML: String) -> String {
        let f = escapeAppleScript(folder)
        let t = escapeAppleScript(title)
        let b = escapeAppleScript(bodyHTML)
        return """
        tell application "Notes"
            if not (exists folder "\(f)") then
                make new folder with properties {name:"\(f)"}
            end if
            set thisFolder to folder "\(f)"
            make new note at thisFolder with properties {name:"\(t)", body:"\(b)"}
        end tell
        """
    }

    /// AppleScript that appends `bodyHTML` to the first note named `title`
    /// inside `folder`. Creates the folder + note when missing (so append
    /// modes are self-healing on first use).
    static func appendScript(folder: String, title: String, bodyHTML: String) -> String {
        let f = escapeAppleScript(folder)
        let t = escapeAppleScript(title)
        let b = escapeAppleScript(bodyHTML)
        return """
        tell application "Notes"
            if not (exists folder "\(f)") then
                make new folder with properties {name:"\(f)"}
            end if
            set thisFolder to folder "\(f)"
            if (exists note "\(t)" of thisFolder) then
                set theNote to note "\(t)" of thisFolder
                set body of theNote to (body of theNote) & "\(b)"
            else
                make new note at thisFolder with properties {name:"\(t)", body:"\(b)"}
            end if
        end tell
        """
    }

    // MARK: - Executor (talks to Notes.app — NOT unit-tested)

    enum NotesError: Error {
        case scriptError(String)
        case timedOut
    }

    /// Resolve the target title + script for the mode, then run it with a 5s
    /// timeout off the main thread. Returns .success on a clean run.
    ///
    /// SIDE EFFECT: sends Apple Events to Notes — triggers the Automation TCC
    /// prompt on first use. Callers MUST only invoke this when the user chose
    /// an Apple Notes destination.
    @discardableResult
    static func write(text: String, mode: NoteMode,
                      folder: String, defaultTitle: String) -> Result<Void, NotesError> {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let now = Date()

        let title = noteTitle(mode: mode, defaultTitle: defaultTitle,
                              text: text, dateString: dateFmt.string(from: now))
        let body = bodyParagraph(timestamp: timeFmt.string(from: now), text: text)

        // newEachTime always creates; the append modes append (self-healing).
        let source = (mode == .newEachTime)
            ? createScript(folder: folder, title: title, bodyHTML: body)
            : appendScript(folder: folder, title: title, bodyHTML: body)

        let sem = DispatchSemaphore(value: 0)
        var runResult: Result<Void, NotesError> = .failure(.timedOut)

        DispatchQueue.global(qos: .userInitiated).async {
            var errInfo: NSDictionary?
            if let osa = NSAppleScript(source: source) {
                _ = osa.executeAndReturnError(&errInfo)
                if let errInfo, let msg = errInfo[NSAppleScript.errorMessage] as? String {
                    runResult = .failure(.scriptError(msg))
                } else if errInfo != nil {
                    runResult = .failure(.scriptError("unknown AppleScript error"))
                } else {
                    runResult = .success(())
                }
            } else {
                runResult = .failure(.scriptError("failed to compile AppleScript"))
            }
            sem.signal()
        }

        if sem.wait(timeout: .now() + 5.0) == .timedOut {
            return .failure(.timedOut)
        }
        return runResult
    }
}
