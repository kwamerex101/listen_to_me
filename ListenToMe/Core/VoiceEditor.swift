import Foundation

/// Inline voice-editing commands. Pure transformation step: feed it a raw
/// Whisper transcript, get back text with spoken punctuation, paragraph
/// breaks, and "scratch that" undos applied. Runs after `CommandRouter.parse`
/// (so utility commands take priority) and before `SnippetsStore.expand`
/// and `ClaudeClient.clean`.
enum VoiceEditor {

    /// Apply all four phases. Pure function — no state, no I/O.
    static func apply(_ text: String) -> String {
        var s = text
        s = applyPunctuation(s)
        s = resolveScratchThat(s)
        s = applyParagraphBreaks(s)
        s = tidy(s)
        return s
    }

    // MARK: - Phase 1 — punctuation substitution

    /// Order matters: longer multi-word patterns come first so a hypothetical
    /// `\bquestion\b` rule (none yet) couldn't pre-empt `\bquestion mark\b`.
    private static let punctuationMap: [(pattern: String, replacement: String)] = [
        ("\\bquestion mark\\b",      "?"),
        ("\\bexclamation point\\b",  "!"),
        ("\\bexclamation mark\\b",   "!"),
        ("\\bfull stop\\b",          "."),
        ("\\bperiod\\b",             "."),
        ("\\bcomma\\b",              ","),
    ]

    private static func applyPunctuation(_ s: String) -> String {
        var out = s
        for (pattern, replacement) in punctuationMap {
            out = replaceWordBoundary(in: out, pattern: pattern, with: replacement)
        }
        return out
    }

    // MARK: - Phase 2 — scratch that

    /// Iteratively resolves each "scratch that" / "delete that" by removing
    /// the preceding sentence (or utterance, if no sentence boundary exists)
    /// along with the command itself.
    private static func resolveScratchThat(_ s: String) -> String {
        let pattern = "\\b(?:scratch|delete) that\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return s
        }
        var current = s
        // Hard cap to defend against pathological inputs. 50 is far more
        // scratch-thats than any real dictation would contain.
        for _ in 0..<50 {
            let nsRange = NSRange(current.startIndex..., in: current)
            guard let match = regex.firstMatch(in: current, options: [], range: nsRange),
                  let matchRange = Range(match.range, in: current) else { break }
            let scopeStart = scopeStartIndex(in: current, beforeMatch: matchRange.lowerBound)
            current.removeSubrange(scopeStart..<matchRange.upperBound)
        }
        return current
    }

    /// Returns the index where the *preceding sentence* starts. The deletion
    /// range is `[scopeStart, end-of-"scratch that")`, which removes the
    /// preceding sentence and the command itself in one go.
    ///
    /// Algorithm: collect all sentence-boundary positions in the prefix;
    /// the preceding sentence starts at the second-to-last boundary (or
    /// string start if there's only the implicit start-of-string boundary).
    private static func scopeStartIndex(in text: String, beforeMatch matchStart: String.Index) -> String.Index {
        let prefix = text[..<matchStart]
        guard !prefix.isEmpty else { return text.startIndex }

        // Boundary = position right after a sentence-terminator (`.!?`) plus
        // any trailing whitespace, OR right after a paragraph break.
        let pattern = "[.!?]+\\s*|\\n\\n+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.startIndex
        }

        var boundaries: [String.Index] = [text.startIndex]
        let nsRange = NSRange(prefix.startIndex..<matchStart, in: text)
        regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            if let m = match, let r = Range(m.range, in: text) {
                boundaries.append(r.upperBound)
            }
        }

        if boundaries.count >= 2 {
            return boundaries[boundaries.count - 2]
        }
        return text.startIndex
    }

    // MARK: - Phase 3 — paragraph & line breaks

    private static let breakMap: [(pattern: String, replacement: String)] = [
        ("\\bnew paragraph\\b", "\n\n"),
        ("\\bnew line\\b",      "\n"),
    ]

    private static func applyParagraphBreaks(_ s: String) -> String {
        var out = s
        for (pattern, replacement) in breakMap {
            out = replaceWordBoundary(in: out, pattern: pattern, with: replacement)
        }
        return out
    }

    // MARK: - Phase 4 — tidy

    private static func tidy(_ s: String) -> String {
        var out = s
        // Collapse runs of horizontal whitespace (but never touch newlines).
        out = out.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        // Strip space immediately before any of `, . ! ?`.
        out = out.replacingOccurrences(of: " ([,.!?])", with: "$1", options: .regularExpression)
        // Insert a single space after `, . ! ?` when followed directly by a letter.
        out = out.replacingOccurrences(of: "([.!?,])([A-Za-z])", with: "$1 $2", options: .regularExpression)
        // Capitalize the first letter of the string and after every `. ! ?` + whitespace
        // and after newlines. Cleanup will redo this for cleaned output, but doing it here
        // makes the *raw* paste under streaming preview already look right.
        out = capitalizeSentences(out)
        // Trim leading/trailing whitespace per line so " hello" → "hello".
        out = out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        // Final outer trim.
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeSentences(_ s: String) -> String {
        let pattern = "(^|[.!?]\\s+|\\n+\\s*)([a-z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let mutable = NSMutableString(string: s)
        let matches = regex.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))
        // Iterate in reverse so earlier ranges don't shift if substitution
        // ever changes length (currently it doesn't, but cheap safety).
        for m in matches.reversed() {
            let letterRange = m.range(at: 2)
            guard letterRange.location != NSNotFound else { continue }
            let sub = mutable.substring(with: letterRange)
            mutable.replaceCharacters(in: letterRange, with: sub.uppercased())
        }
        return mutable as String
    }

    // MARK: - Shared regex helper (mirrors SnippetsStore.expand)

    private static func replaceWordBoundary(in text: String,
                                            pattern: String,
                                            with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
