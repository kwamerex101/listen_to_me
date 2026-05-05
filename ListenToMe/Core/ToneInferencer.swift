import Foundation

/// Deterministic per-app tone classification used by Phase 4 (Per-App Style
/// Tuning). Pure: no I/O, no `@MainActor`. Operates on cleaned-text samples
/// captured by `StyleSamplesStore` after each successful paste.
///
/// Returns `.none` until at least 20 samples are available; this matches the
/// suggestion-fire threshold so ambiguous early data never produces a banner.
enum InferredTone: String, Codable, CaseIterable {
    case formal, casual, code, markdown, none

    /// STYLE NOTE prepended above `ClaudeClient.cleanupSystemPrompt`.
    /// Returns `nil` for `.none`, in which case the caller falls back to the
    /// default cleanup prompt unchanged. Strings reproduced verbatim from
    /// `04-RESEARCH.md` Q4.
    var promptHint: String? {
        switch self {
        case .casual:
            return """
            STYLE NOTE: The user is writing into a casual messaging context.
            When fixing punctuation/capitalization, prefer informal conventions:
            keep contractions (don't expand "I'll" to "I will"), allow lowercase
            sentence starts when the original lacks capitalization signals,
            and prefer commas over semicolons. Do NOT add formality the speaker
            did not use. All HARD RULES below still apply.
            """
        case .formal:
            return """
            STYLE NOTE: The user is writing into a formal context (document or email).
            Apply standard prose conventions: full sentence capitalization, terminal
            punctuation, expand stuttered or trailed-off clauses to complete sentences
            ONLY when the speaker's intent is unambiguous. Do NOT add words the
            speaker did not say. All HARD RULES below still apply.
            """
        case .code:
            return """
            STYLE NOTE: The user is dictating into a code editor or technical context.
            Preserve identifier-like tokens verbatim (camelCase, snake_case, dotted.paths).
            Do NOT auto-capitalize identifiers. Do NOT auto-punctuate code-shaped
            text. If the input looks like prose interleaved with code, keep both
            as-is. All HARD RULES below still apply.
            """
        case .markdown:
            return """
            STYLE NOTE: The user is writing into a markdown editor. Preserve
            markdown syntax (`#`, `-`, `*`, `[]()`) verbatim. Apply standard prose
            cleanup to body text only. Do NOT convert markdown to prose. All
            HARD RULES below still apply.
            """
        case .none:
            return nil
        }
    }

    /// Human-readable label for UI. Lowercase to match banner copy
    /// ("Suggesting **casual** tone for Slack").
    var displayLabel: String { rawValue }
}

enum ToneInferencer {
    /// Infer a tone from the cleaned-text samples captured for one bundleId.
    /// Returns `.none` for fewer than 20 samples or when no clause trips.
    static func infer(samples: [String]) -> InferredTone {
        guard samples.count >= 20 else { return .none }
        let f = featureVector(samples)
        if f.codeFence >= 0.20 || (f.inlineCode >= 0.30 && f.indent >= 0.30) { return .code }
        if f.mdSyntax >= 0.30 { return .markdown }
        if f.contraction >= 3.0 || f.firstPerson >= 4.0 || f.nonAscii >= 0.20 || f.avgSentLen <= 10 {
            return .casual
        }
        if f.avgSentLen >= 18 && f.contraction <= 0.5 && f.formalLex >= 0.5 { return .formal }
        return .none
    }

    private struct Features {
        var codeFence: Double; var inlineCode: Double; var mdSyntax: Double
        var avgSentLen: Double; var contraction: Double; var firstPerson: Double
        var formalLex: Double; var nonAscii: Double; var indent: Double
    }

    private static func featureVector(_ samples: [String]) -> Features {
        let n = Double(samples.count)
        let codeFence = samples.filter { $0.contains("```") }.count
        let inlineCode = samples.filter { $0.range(of: #"`[^`]+`"#, options: .regularExpression) != nil }.count
        let mdRegex = #"(?m)^(#{1,6} |[-*] |\d+\. )|\[.+?\]\(.+?\)|\*\*.+?\*\*"#
        let md = samples.filter { $0.range(of: mdRegex, options: .regularExpression) != nil }.count
        let nonAscii = samples.filter { $0.range(of: #"[^\x00-\x7F]"#, options: .regularExpression) != nil }.count
        let indent = samples.filter { $0.range(of: #"(?m)^\s{2,}"#, options: .regularExpression) != nil }.count
        let allText = samples.joined(separator: " ")
        let words = max(allText.split(whereSeparator: \.isWhitespace).count, 1)
        let sentences = max(allText.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count, 1)
        let contractions = countMatches(allText, #"\b\w+'(s|t|re|ll|ve|d|m)\b"#)
        let firstP = countMatches(allText.lowercased(), #"\b(i|me|my|we|us|our)\b"#)
        let formalLex = countMatches(allText.lowercased(), #"\b(furthermore|therefore|moreover|regarding|pursuant|accordingly|whereby|hereby)\b"#)
        return Features(
            codeFence: Double(codeFence)/n, inlineCode: Double(inlineCode)/n,
            mdSyntax: Double(md)/n, avgSentLen: Double(words)/Double(sentences),
            contraction: Double(contractions)/Double(words)*100,
            firstPerson: Double(firstP)/Double(words)*100,
            formalLex: Double(formalLex)/Double(words)*100,
            nonAscii: Double(nonAscii)/n, indent: Double(indent)/n
        )
    }

    private static func countMatches(_ s: String, _ pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }
}
