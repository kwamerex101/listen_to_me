import Foundation

/// Mines auto-dictionary candidates from HistoryStore by looking for
/// places where the cleanup pass (`finalText`) consistently swapped a
/// single word that whisper got wrong (`rawText`). Pure analysis: no
/// I/O, no MainActor — runs on a background priority off the audio
/// pipeline.
///
/// Why this exists: the existing CandidateStore is fed by retype
/// detection (user manually corrected the paste within 7s). That misses
/// the much larger signal sitting in history: every time claude cleaned
/// up "danqua" → "Danquah", we already know whisper's mangled rendering
/// AND the right answer — but that knowledge was discarded.
///
/// Pipeline contribution: feeding these into DictionaryStore.whisperPrompt
/// biases future whisper transcriptions toward the correct rendering,
/// which removes a cleanup round-trip and the latency / occasional
/// hallucination risk that comes with it.
enum HistoryDictionaryMiner {
    struct Swap: Equatable, Hashable {
        let original: String      // raw whisper rendering
        let replacement: String   // cleaned-up form
    }

    /// Walk `records` and return single-word swaps `(rawWord →
    /// cleanedWord)` where the diff between rawText and finalText is
    /// exactly one token. Keeps the signal high — multi-word diffs are
    /// usually the cleanup pass restructuring the sentence rather than
    /// fixing a name.
    ///
    /// Caller is expected to feed the result into
    /// `CandidateStore.ingestMined(_:)`, which respects the existing
    /// 3-distinct-occurrences promotion threshold.
    static func mine(records: [(rawText: String, finalText: String, bundleId: String?)]) -> [(swap: Swap, bundleId: String?)] {
        var hits: [(swap: Swap, bundleId: String?)] = []
        for r in records {
            // Skip records where cleanup didn't run (raw == final means
            // either cleanup was off or the cleanup output equaled the
            // input — no signal either way).
            guard !r.rawText.isEmpty, !r.finalText.isEmpty,
                  r.rawText != r.finalText else { continue }
            guard let swap = singleWordSwap(rawText: r.rawText, finalText: r.finalText) else { continue }
            // Quality filters: don't mine pure-punctuation or 1-char
            // swaps; whisper is fine on those, the noise isn't worth it.
            guard swap.original.count >= 3, swap.replacement.count >= 3 else { continue }
            // Skip if either side contains punctuation other than
            // apostrophe/hyphen — usually a tokenization artifact.
            let allowed = CharacterSet.letters
                .union(CharacterSet(charactersIn: "'-"))
            if !swap.original.unicodeScalars.allSatisfy(allowed.contains) { continue }
            if !swap.replacement.unicodeScalars.allSatisfy(allowed.contains) { continue }
            hits.append((swap, r.bundleId))
        }
        return hits
    }

    /// If `rawText` and `finalText` differ by exactly one word swap
    /// (same word count, single position differs), return that swap.
    /// Otherwise nil.
    private static func singleWordSwap(rawText: String, finalText: String) -> Swap? {
        let rawTokens = rawText.split(whereSeparator: \.isWhitespace).map(String.init)
        let cleanTokens = finalText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard rawTokens.count == cleanTokens.count, rawTokens.count > 0 else { return nil }
        var diffIndex: Int? = nil
        for i in rawTokens.indices {
            // Strip trailing punctuation for comparison so "danqua." vs
            // "Danquah." doesn't fail on the period.
            let rawNorm = stripTrailingPunct(rawTokens[i])
            let cleanNorm = stripTrailingPunct(cleanTokens[i])
            if rawNorm.lowercased() != cleanNorm.lowercased() {
                if diffIndex != nil { return nil }   // ≥2 diffs → not a single-word swap
                diffIndex = i
            }
        }
        guard let idx = diffIndex else { return nil }
        let original = stripTrailingPunct(rawTokens[idx])
        let replacement = stripTrailingPunct(cleanTokens[idx])
        // Don't mine if the only difference is capitalization — whisper
        // capitalization is usually the cleanup pass's job, not a
        // dictionary fix.
        guard original.lowercased() != replacement.lowercased() else { return nil }
        return Swap(original: original, replacement: replacement)
    }

    private static func stripTrailingPunct(_ s: String) -> String {
        let punct = CharacterSet(charactersIn: ".,;:!?\"')(”’`")
        var out = s
        while let last = out.unicodeScalars.last, punct.contains(last) {
            out.removeLast()
        }
        // Also strip leading.
        while let first = out.unicodeScalars.first, punct.contains(first) {
            out.removeFirst()
        }
        return out
    }
}
