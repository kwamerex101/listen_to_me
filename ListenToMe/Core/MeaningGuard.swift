import Foundation

/// Rejects a cleanup that changed the *meaning* of the transcript — dropped
/// most content words, invented new ones, or grossly expanded/truncated —
/// and tells the caller to fall back to the raw input. This is the system
/// guaranteeing "if unsure, leave it unchanged", rather than trusting the
/// model (critical for the local 2B Gemma, which over-edits).
///
/// Built on `CleanupMetrics`. Used by `ClaudeClient.sanitize` after its
/// surface cleanup (quote/fence/preamble stripping).
///
/// Thresholds are deliberately LENIENT for now: they catch gross failures
/// (bulk hallucination, rewrites, explosion) without rejecting legitimate
/// per-word fixes like a proper-noun spelling correction ("danqua" →
/// "Danquah"). The Wave 7 eval harness will calibrate them against real
/// raw→ideal pairs; until then, false-negatives (letting a bad edit through)
/// are preferable to false-positives (rejecting good cleanups and degrading
/// the feature).
enum MeaningGuard {

    struct Thresholds {
        /// Min fraction of the original's content words that must survive.
        var minRecall: Double = 0.5
        /// Max fraction of the candidate's content words allowed to be absent
        /// from the original (invented content).
        var maxHallucination: Double = 0.5
        /// Min content-word Jaccard between original and candidate.
        var minJaccard: Double = 0.3
        /// Allowed candidate/original word-count ratio. Lower bound is loose
        /// because heavy filler removal legitimately compresses a lot.
        var minLengthRatio: Double = 0.3
        var maxLengthRatio: Double = 1.4
        /// When true, reject a cleanup that drops a negation ("Do not
        /// deploy" → "Deploy") or loses a number that appeared in the
        /// original ("15" → "50"). These invert or falsify the sentence in
        /// ways the content-word metrics above can't see — nearly every
        /// word survives either failure. Off for transformations that
        /// legitimately change numbers/polarity on purpose (a translation,
        /// or a Backtrack revision like "make that not urgent").
        var preserveNegationAndNumbers: Bool = true

        static let `default` = Thresholds()

        /// Surface-only checks for an explicit user-requested transform
        /// (translate/summarize/bulletize/etc. via `ClaudeClient.transform`):
        /// the user asked for a rewrite, so meaning-preservation and
        /// negation/number checks would reject almost every legitimate
        /// result. `sanitize`'s surface cleanup (quotes, fences, preamble,
        /// empty output) still applies.
        static let transform: Thresholds = {
            var t = Thresholds(minRecall: 0, maxHallucination: 1, minJaccard: 0,
                               minLengthRatio: 0, maxLengthRatio: .infinity)
            t.preserveNegationAndNumbers = false
            return t
        }()

        /// Thresholds per cleanup intensity. Higher intensity = looser guard,
        /// because more aggressive editing legitimately drops/reorders words.
        /// `.light` keeps the validated defaults; `.high` only catches gross
        /// garbage (a rewrite is expected to diverge). Negation/number
        /// preservation stays on at every intensity — cleanup, unlike an
        /// explicit transform/rewrite, should never silently flip "not" or a
        /// number no matter how aggressively it's asked to edit.
        static func of(_ intensity: Preferences.CleanupIntensity) -> Thresholds {
            switch intensity {
            case .light:
                return Thresholds()   // defaults
            case .medium:
                return Thresholds(minRecall: 0.4, maxHallucination: 0.55,
                                  minJaccard: 0.25, minLengthRatio: 0.3, maxLengthRatio: 1.6)
            case .high:
                return Thresholds(minRecall: 0.2, maxHallucination: 0.8,
                                  minJaccard: 0.1, minLengthRatio: 0.2, maxLengthRatio: 2.5)
            }
        }
    }

    enum Decision: Equatable {
        case accept
        case reject(reason: String)

        var isAccept: Bool { if case .accept = self { return true }; return false }
    }

    /// Evaluate `cleaned` against the raw `original`. The original is both the
    /// content-preservation reference and the allowed-vocabulary source.
    static func evaluate(cleaned: String,
                         original: String,
                         thresholds t: Thresholds = .default) -> Decision {
        // Nothing to compare against — accept (an empty original means the
        // surface checks already had their say).
        if CleanupMetrics.contentWords(original).isEmpty { return .accept }

        // Interrogative preservation: a cleanup must not turn a question into
        // a statement. When the original ends with '?' the candidate must too
        // — otherwise the intent (a question/request) was silently inverted,
        // a failure the content-word metrics below can't see because nearly
        // every word survives (observed live: "Can we get X?" → "I can get X.").
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTrimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if originalTrimmed.hasSuffix("?") && !cleanedTrimmed.hasSuffix("?") {
            return .reject(reason: "interrogative flattened to declarative")
        }

        // Negation/number preservation runs before the metric checks below:
        // both failures leave nearly every content word intact (only the
        // polarity or a digit changed), so recall/hallucination/jaccard
        // would happily accept them.
        if t.preserveNegationAndNumbers {
            let originalNegations = negationCount(originalTrimmed)
            let cleanedNegations = negationCount(cleanedTrimmed)
            if cleanedNegations < originalNegations {
                return .reject(reason: "negation dropped")
            }
            if !numbersPreserved(original: originalTrimmed, cleaned: cleanedTrimmed) {
                return .reject(reason: "number changed")
            }
        }

        let recall = CleanupMetrics.contentWordRecall(candidate: cleaned, reference: original)
        if recall < t.minRecall {
            return .reject(reason: "recall \(fmt(recall)) < \(fmt(t.minRecall))")
        }

        let halluc = CleanupMetrics.hallucinationRate(candidate: cleaned, raw: original)
        if halluc > t.maxHallucination {
            return .reject(reason: "hallucination \(fmt(halluc)) > \(fmt(t.maxHallucination))")
        }

        let jaccard = CleanupMetrics.contentJaccard(original, cleaned)
        if jaccard < t.minJaccard {
            return .reject(reason: "jaccard \(fmt(jaccard)) < \(fmt(t.minJaccard))")
        }

        let ratio = CleanupMetrics.lengthRatio(candidate: cleaned, raw: original)
        if ratio < t.minLengthRatio || ratio > t.maxLengthRatio {
            return .reject(reason: "lengthRatio \(fmt(ratio)) outside [\(fmt(t.minLengthRatio)), \(fmt(t.maxLengthRatio))]")
        }

        return .accept
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

    // MARK: - Negation preservation

    /// Words that negate the clause they're in. Checked after normalizing
    /// contractions ("n't" → " not", "cannot" → "can not") so "don't",
    /// "won't", "can't" all count.
    private static let negators: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "nowhere",
        "neither", "nor", "without",
    ]

    /// Count of negators in `text`, tokenized on letters only (lowercased),
    /// with immediately-repeated identical negators collapsed to one — a
    /// speech stutter ("no no, we won't") shouldn't inflate the count and
    /// then get flagged as "dropped" when the cleanup naturally de-stutters
    /// it.
    static func negationCount(_ text: String) -> Int {
        var normalized = text.lowercased()
        normalized = normalized.replacingOccurrences(of: "n't", with: " not")
        normalized = normalized.replacingOccurrences(of: "cannot", with: "can not")

        var words: [String] = []
        var current = ""
        for ch in normalized {
            if ch.isLetter {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        var count = 0
        var previous: String?
        for word in words {
            if negators.contains(word) {
                if word != previous { count += 1 }
            }
            previous = word
        }
        return count
    }

    // MARK: - Number preservation

    /// Extract the multiset of numbers in `text` as canonical strings:
    /// digit runs with thousands separators ("1,000") stripped and decimal
    /// points ("3.5") kept.
    static func numberTokens(_ text: String) -> [String] {
        let chars = Array(text)
        var tokens: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isNumber {
                current.append(ch)
                i += 1
            } else if !current.isEmpty, ch == ",", i + 1 < chars.count, chars[i + 1].isNumber {
                // Thousands separator inside an active run — drop it, keep the run going.
                i += 1
            } else if !current.isEmpty, ch == ".", i + 1 < chars.count, chars[i + 1].isNumber {
                // Decimal point inside an active run — keep it.
                current.append(ch)
                i += 1
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                i += 1
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// True when every number that appeared in `original` still appears in
    /// `cleaned`, as a multiset (a repeated number must survive the same
    /// number of times). `cleaned` may contain additional numbers not in
    /// `original` — cleanup turning "fifteen" into "15" is a legitimate
    /// improvement, not a drift.
    static func numbersPreserved(original: String, cleaned: String) -> Bool {
        let originalNumbers = numberTokens(original)
        if originalNumbers.isEmpty { return true }
        var remaining: [String: Int] = [:]
        for n in numberTokens(cleaned) { remaining[n, default: 0] += 1 }
        for n in originalNumbers {
            guard let count = remaining[n], count > 0 else { return false }
            remaining[n] = count - 1
        }
        return true
    }
}
