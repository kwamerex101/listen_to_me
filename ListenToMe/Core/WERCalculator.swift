import Foundation

/// Word Error Rate against a known reference — the benchmark's accuracy
/// metric. Unlike cleanup scoring (CleanupMetrics), WER is RIGHT here: the
/// user reads a fixed card aloud, so the reference is exact and every
/// substitution/insertion/deletion is a real ASR error.
enum WERCalculator {

    /// Lowercase, strip punctuation, collapse whitespace, and normalize the
    /// formatting choices that aren't real ASR errors: digit words ("3" vs
    /// "three"), the a.m./p.m. abbreviation (which otherwise tokenizes as two
    /// letters), and British vs US spellings. These are presentation
    /// differences, not mishears — counting them as errors inflates WER (as
    /// the first benchmark run showed).
    static func normalize(_ text: String) -> [String] {
        let digitWords: [String: String] = [
            "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
            "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
            "10": "ten", "11": "eleven", "12": "twelve", "20": "twenty",
            "30": "thirty", "100": "hundred",
        ]
        // British → US, applied per token so spelling variants don't count.
        let spelling: [String: String] = [
            "harbour": "harbor", "colour": "color", "favour": "favor",
            "honour": "honor", "labour": "labor", "neighbour": "neighbor",
            "behaviour": "behavior", "organise": "organize",
            "organisation": "organization", "recognise": "recognize",
            "analyse": "analyze", "centre": "center", "metre": "meter",
            "litre": "liter", "theatre": "theater", "cancelled": "canceled",
            "travelled": "traveled", "grey": "gray",
        ]

        // Pre-collapse a.m./p.m. (with or without periods/spaces) to single
        // tokens before splitting, so "p.m." doesn't become ["p","m"].
        var pre = text.lowercased()
        for (pat, repl) in [("a.m.", " am "), ("p.m.", " pm "),
                            ("a. m.", " am "), ("p. m.", " pm ")] {
            pre = pre.replacingOccurrences(of: pat, with: repl)
        }

        var words: [String] = []
        var current = ""
        for ch in pre {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if ch == "'" || ch == "\u{2019}" {
                continue
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { spelling[$0] ?? digitWords[$0] ?? $0 }
    }

    /// Word-level Levenshtein distance / reference length. 0.0 = perfect.
    /// Empty reference: 0 if hypothesis also empty, else 1.
    static func wer(reference: String, hypothesis: String) -> Double {
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        if ref.isEmpty { return hyp.isEmpty ? 0.0 : 1.0 }

        // Classic two-row DP.
        var prev = Array(0...hyp.count)
        var curr = [Int](repeating: 0, count: hyp.count + 1)
        for i in 1...ref.count {
            curr[0] = i
            for j in 1...hyp.count {
                let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1,        // deletion
                              curr[j - 1] + 1,    // insertion
                              prev[j - 1] + cost) // substitution
            }
            swap(&prev, &curr)
        }
        return Double(prev[hyp.count]) / Double(ref.count)
    }
}
