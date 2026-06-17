import Foundation

/// Inline voice-editing commands. Pure transformation step: feed it a raw
/// Whisper transcript, get back text with spoken punctuation, paragraph
/// breaks, and "scratch that" undos applied. Runs after `CommandRouter.parse`
/// (so utility commands take priority) and before `SnippetsStore.expand`
/// and `ClaudeClient.clean`.
enum VoiceEditor {

    /// Apply all phases. Pure function — no state, no I/O.
    ///
    /// `terms` are canonical-cased dictionary entries — acronyms ("KYC"),
    /// mixed-case single words ("GitHub", "iPhone"), and multi-word proper
    /// nouns ("Face ID") — that should be rewritten to their exact casing
    /// wherever they appear. Build it via `canonicalTerms(from:)`. Empty by
    /// default so callers that don't care stay unchanged.
    static func apply(_ text: String, terms: [String] = []) -> String {
        var s = text
        s = collapseRepeatedWords(s)
        s = applyPunctuation(s)
        s = resolveScratchThat(s)
        s = applyParagraphBreaks(s)
        s = tidy(s)
        // Runs AFTER tidy on purpose: tidy inserts a space after `.` before a
        // letter, which would re-split "readme.md" back into "readme. md".
        s = joinDottedTokens(s)
        s = joinSpokenOperators(s)
        // Last: tidy's sentence-capitalization only touches first letters, so
        // it can't undo a canonical casing like "KYC" or "Face ID".
        s = applyCanonicalCasing(s, terms)
        return s
    }

    // MARK: - Phase 7 — dictionary-seeded canonical casing ("face id" → "Face ID")

    /// Short English words that must never be force-cased even if a user adds
    /// them as an all-caps dictionary entry — guards against "IT" turning every
    /// "it" into "IT". Only applies to single all-caps tokens; mixed-case and
    /// multi-word terms can't collide with ordinary prose, so they skip it.
    private static let acronymStopwords: Set<String> = [
        "a", "i", "an", "as", "at", "am", "be", "by", "do", "go", "he", "if",
        "in", "is", "it", "me", "my", "no", "of", "ok", "on", "or", "so", "to",
        "up", "us", "we", "and",
    ]

    /// Derive canonical-casing terms from dictionary words: any entry that
    /// carries an uppercase letter (the user deliberately cased it). A bare
    /// single all-caps token (an acronym like "KYC") is length-capped and
    /// stopword-guarded so it can't uppercase ordinary words; mixed-case and
    /// multi-word terms ("GitHub", "Face ID") are exempt from those guards.
    /// All-lowercase entries are ignored — there's no casing to enforce.
    /// Returned longest-first so "Face ID" wins before a lone "ID".
    static func canonicalTerms(from words: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for w in words {
            let t = w.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2, t.contains(where: { $0.isUppercase }) else { continue }
            let isSingleAllCaps = !t.contains(" ")
                && t.allSatisfy { $0.isLetter && $0.isUppercase }
            if isSingleAllCaps,
               t.count > 6 || acronymStopwords.contains(t.lowercased()) {
                continue
            }
            if seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out.sorted { $0.count > $1.count }
    }

    /// Rewrite each case-insensitive whole-phrase occurrence to the term's
    /// exact casing. Multi-word terms match across flexible inter-word
    /// whitespace ("face   id" → "Face ID").
    private static func applyCanonicalCasing(_ s: String, _ terms: [String]) -> String {
        guard !terms.isEmpty else { return s }
        var out = s
        for term in terms {
            let tokens = term.split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !tokens.isEmpty else { continue }
            let pattern = "\\b" + tokens.joined(separator: "\\s+") + "\\b"
            out = regexReplaceTemplate(out, pattern, NSRegularExpression.escapedTemplate(for: term))
        }
        return out
    }

    // MARK: - Phase 0 — collapse stuttered repeats ("detector detector" → "detector")

    /// Words that are legitimately or emphatically doubled in normal speech —
    /// never collapsed. Everything else, when immediately repeated, is treated
    /// as a stutter ("the the" / "detector detector" / "and and").
    private static let repeatPreserve: Set<String> = [
        "had", "that", "very", "really", "so", "no", "night",
        "bye", "yeah", "ha", "mm", "hmm", "blah",
    ]

    /// Collapse an immediately-repeated word (case-insensitive, space-separated
    /// only — never across punctuation) down to its first occurrence. Keeps the
    /// first token's casing. Skips the emphatic/grammatical doubles above and
    /// pure-digit runs (e.g. dictating a number twice on purpose).
    private static func collapseRepeatedWords(_ s: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: "\\b(\\w+)(?:[ \\t]+\\1\\b)+",
            options: [.caseInsensitive]) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }

        var result = ""
        var cursor = 0
        for m in matches {
            let whole = m.range
            let first = ns.substring(with: m.range(at: 1))
            result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            let lower = first.lowercased()
            let isDigits = first.allSatisfy { $0.isNumber }
            if repeatPreserve.contains(lower) || isDigits {
                result += ns.substring(with: whole)   // keep the repeat
            } else {
                result += first                        // collapse to one
            }
            cursor = whole.location + whole.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: - Phase 6 — spoken operators ("plus" → "+")

    /// Convert spoken "plus" into "+" only in unambiguous contexts, so prose
    /// like "2 plus 2 more chairs" or "plus one" is left untouched:
    ///   • semver build metadata: "1.0.29 plus 230" → "1.0.29+230"
    ///     (left side must be a dotted version, so a bare "2 plus 2" is skipped)
    ///   • the language idiom: "C plus plus" → "C++"
    private static func joinSpokenOperators(_ s: String) -> String {
        var out = s
        // "C plus plus" → "C++" (before the version rule so the two "plus"
        // tokens aren't half-consumed).
        out = regexReplaceTemplate(out, "\\bc\\s+plus\\s+plus\\b", "C++")
        // Dotted-version + build number: "<maj.min[.patch…]> plus <digits>".
        out = regexReplaceTemplate(
            out,
            "\\b(\\d+\\.\\d+(?:\\.\\d+)*)\\s+plus\\s+(\\d+)\\b",
            "$1+$2")
        return out
    }

    // MARK: - Phase 5 — spoken "dot" in file names / domains / decimals

    /// File extensions and TLDs where a spoken "dot" almost certainly means a
    /// literal "." — high precision so prose like "the dot product" is left
    /// alone (neither "product" nor "matrix" is in these lists).
    private static let dotSuffixes =
        // file extensions
        "md|markdown|txt|swift|py|js|jsx|ts|tsx|json|yaml|yml|sh|rb|go|rs|java|" +
        "kt|kts|c|cc|cpp|h|hpp|m|mm|css|scss|html|htm|xml|toml|lock|cfg|ini|" +
        "env|plist|gitignore|png|jpg|jpeg|gif|svg|pdf|csv|tsv|log|sql|zip|gz|" +
        // common TLDs
        "com|org|net|io|dev|app|co|ai|gov|edu|me|xyz|cloud|tech"

    /// Determiners/articles that should NOT glue to a following extension:
    /// "all the dot md files" → "all the .md files", not "the.md".
    private static let dotLeadingStopwords =
        "the|a|an|all|some|these|those|this|that|my|your|our|their|its|any|each|every|no"

    /// Convert spoken "<x> dot <ext>" into "<x>.<ext>" for known extensions,
    /// TLDs, and numeric decimals. Determiner-led cases attach the dot to the
    /// extension only ("the .md") rather than gluing the article.
    private static func joinDottedTokens(_ s: String) -> String {
        var out = s
        let suffix = "(?:\(dotSuffixes))"
        // 1) Determiner first → ". ext" stays detached from the determiner.
        out = regexReplaceTemplate(
            out,
            "\\b(\(dotLeadingStopwords))\\s+dot\\s+(\(suffix))\\b",
            "$1 .$2")
        // 2) Any remaining "word dot ext" → glue ("readme.md", "node.js").
        out = regexReplaceTemplate(
            out,
            "\\b(\\w+)\\s+dot\\s+(\(suffix))\\b",
            "$1.$2")
        // 3) Numeric decimals: "3 dot 14" → "3.14".
        out = regexReplaceTemplate(
            out,
            "\\b(\\d+)\\s+dot\\s+(\\d+)\\b",
            "$1.$2")
        return out
    }

    /// Case-insensitive regex substitution with `$n` capture-group templates.
    private static func regexReplaceTemplate(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
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
