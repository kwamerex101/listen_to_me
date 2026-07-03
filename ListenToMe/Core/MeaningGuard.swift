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

        static let `default` = Thresholds()

        /// Thresholds per cleanup intensity. Higher intensity = looser guard,
        /// because more aggressive editing legitimately drops/reorders words.
        /// `.light` keeps the validated defaults; `.high` only catches gross
        /// garbage (a rewrite is expected to diverge).
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
}
