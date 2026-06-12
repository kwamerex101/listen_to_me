import Foundation

/// Decides whether the LLM cleanup pass is worth running. Extends the
/// word-count gate (CleanupMode) with a *messiness* check: under the smart
/// modes, skip cleanup when the transcript is already clean. Two wins —
/// latency (no model call) and quality (a clean transcript can't be degraded
/// by an over-eager model, the dominant local-LLM failure).
///
/// `.always` and `.off` are explicit user choices and are respected verbatim;
/// the clean-text skip only refines the "smart" (heuristic) modes.
enum CleanupGate {

    static func shouldClean(text: String, wordCount: Int, mode: CleanupMode) -> Bool {
        switch mode {
        case .off:
            return false
        case .always:
            return true
        case .smart20, .smart50:
            guard let t = mode.threshold, wordCount > t else { return false }
            return !isAlreadyClean(text)
        }
    }

    /// True when the text shows no signs of needing cleanup: no filler words,
    /// no adjacent duplicate words (stutters), terminal punctuation present,
    /// and a capitalized first letter. Conservative — any doubt → not clean
    /// (so we'd still run cleanup), since a false "clean" skips a useful pass
    /// whereas a false "messy" only costs one model call.
    static func isAlreadyClean(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }   // nothing to clean

        // Tokenize to lowercased word forms (apostrophes collapsed), keeping
        // ALL words (fillers/stopwords included) so we can detect them.
        var words: [String] = []
        var current = ""
        for ch in trimmed.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if ch == "'" || ch == "\u{2019}" {
                continue
            } else if !current.isEmpty {
                words.append(current); current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        // Filler present → messy.
        if words.contains(where: { CleanupMetrics.fillers.contains($0) }) { return false }

        // Adjacent duplicate word (stutter) → messy.
        for i in 1..<max(words.count, 1) where i < words.count {
            if words[i] == words[i - 1] { return false }
        }

        // Missing terminal punctuation → messy (needs a period etc.).
        if let last = trimmed.unicodeScalars.last,
           !".?!".unicodeScalars.contains(last) {
            return false
        }

        // First letter not capitalized → messy.
        if let firstLetter = trimmed.first(where: { $0.isLetter }),
           firstLetter.isLowercase {
            return false
        }

        return true
    }
}
