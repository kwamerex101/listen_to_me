import Foundation

/// Pure, model-free metrics for transcript cleanup. Used by two things:
///   1. The eval harness — score a candidate cleanup against a reference.
///   2. The meaning-preservation guard — reject a cleanup that dropped or
///      invented content words (Wave 7 P0).
///
/// Why not WER-against-reference: cleanup INTENTIONALLY changes the text
/// (removes fillers, fixes punctuation), so WER would punish correct edits.
/// The metric that matters is whether *content words* survived and whether
/// any were *invented* — that's what catches the real failure (silently
/// wrong/added meaning).
enum CleanupMetrics {

    /// Disfluency fillers — removed before comparison so dropping them never
    /// counts against a cleanup. Lowercased, matched as whole tokens.
    static let fillers: Set<String> = [
        "um", "uh", "er", "uhm", "erm", "mm", "hmm", "ah", "eh",
        "like", "literally", "basically", "actually", "honestly",
    ]

    /// High-frequency function words. Excluded from content-word comparison so
    /// punctuation/grammar fixes that add or drop a stopword (e.g. inserting
    /// "the") don't register as meaning changes.
    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "to", "of", "in", "on",
        "at", "for", "with", "as", "by", "is", "are", "was", "were", "be",
        "been", "am", "i", "you", "he", "she", "it", "we", "they", "this",
        "that", "these", "those", "my", "your", "our", "their", "do", "did",
        "does", "have", "has", "had", "will", "would", "can", "could",
    ]

    /// Tokenize to lowercased content words: split on non-alphanumerics, drop
    /// fillers and stopwords. Apostrophes inside words are preserved as the
    /// word boundary (so "don't" → "dont", "i'm" → "im") to keep contraction
    /// expansion from looking like content change.
    static func contentWords(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var words: [String] = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if ch == "'" || ch == "\u{2019}" {
                // drop the apostrophe, keep the word contiguous
                continue
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.filter { !fillers.contains($0) && !stopwords.contains($0) }
    }

    /// Fraction of the reference's content words that also appear in the
    /// candidate. 1.0 = every meaningful word survived. Empty reference → 1.0
    /// (nothing to preserve).
    static func contentWordRecall(candidate: String, reference: String) -> Double {
        let ref = Set(contentWords(reference))
        guard !ref.isEmpty else { return 1.0 }
        let cand = Set(contentWords(candidate))
        let kept = ref.intersection(cand).count
        return Double(kept) / Double(ref.count)
    }

    /// Fraction of the candidate's content words that DON'T appear in the
    /// allowed sources (the raw input, plus an optional reference). High =
    /// the cleanup invented content (hallucination). Empty candidate → 0.0.
    static func hallucinationRate(candidate: String, raw: String, reference: String? = nil) -> Double {
        let cand = contentWords(candidate)
        guard !cand.isEmpty else { return 0.0 }
        var allowed = Set(contentWords(raw))
        if let reference { allowed.formUnion(contentWords(reference)) }
        let invented = cand.filter { !allowed.contains($0) }.count
        return Double(invented) / Double(cand.count)
    }

    /// Jaccard similarity of the two texts' content-word sets: |A∩B| / |A∪B|.
    /// Both empty → 1.0. Single tunable knob for "did the meaning drift".
    static func contentJaccard(_ a: String, _ b: String) -> Double {
        let sa = Set(contentWords(a))
        let sb = Set(contentWords(b))
        if sa.isEmpty && sb.isEmpty { return 1.0 }
        let inter = sa.intersection(sb).count
        let union = sa.union(sb).count
        return union == 0 ? 1.0 : Double(inter) / Double(union)
    }

    /// Word-count ratio candidate/raw. Cleanup removes fillers/stutters, so a
    /// faithful result is normally ~0.5–1.1×; far outside that signals
    /// over-deletion/truncation (low) or expansion/commentary (high).
    static func lengthRatio(candidate: String, raw: String) -> Double {
        let rawWords = raw.split(whereSeparator: { $0.isWhitespace }).count
        guard rawWords > 0 else { return candidate.isEmpty ? 1.0 : Double.infinity }
        let candWords = candidate.split(whereSeparator: { $0.isWhitespace }).count
        return Double(candWords) / Double(rawWords)
    }
}
