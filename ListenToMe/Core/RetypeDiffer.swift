import Foundation

// MARK: - Tokenization

/// Word tokens using Unicode-aware word boundaries (Foundation .byWords).
/// Punctuation at token edges is stripped automatically — satisfies D-13.
func tokenize(_ s: String) -> [String] {
    var tokens: [String] = []
    s.enumerateSubstrings(in: s.startIndex..., options: .byWords) { sub, _, _, _ in
        if let sub { tokens.append(sub) }
    }
    return tokens
}

// MARK: - Single-word swap detection

/// Returns (original_token, replacement_token) if `current` contains exactly
/// one N-token window (N = origTokens.count) that differs from `original` by
/// exactly one position. This sliding-window form makes detection robust to
/// surrounding text in the target field (other paragraphs, prior content).
/// If multiple equally-good windows exist the result is ambiguous and we
/// reject (D-13 conservative-capture). Case-sensitive (D-12).
func singleWordSwap(from original: String, to current: String) -> (String, String)? {
    let origTokens = tokenize(original)
    let curTokens  = tokenize(current)
    let n = origTokens.count
    guard n > 0, curTokens.count >= n else { return nil }

    var bestStart: Int? = nil
    var bestDiffIdx: Int? = nil

    for start in 0...(curTokens.count - n) {
        var diffIdx: Int? = nil
        var multiple = false
        for i in 0..<n {
            if origTokens[i] != curTokens[start + i] {
                if diffIdx != nil { multiple = true; break }
                diffIdx = i
            }
        }
        if multiple { continue }
        guard let idx = diffIdx else { continue }  // exact match — try next window
        // Found a candidate window with exactly one diff.
        if bestStart != nil { return nil }  // ambiguous — reject
        bestStart = start
        bestDiffIdx = idx
    }

    guard let start = bestStart, let i = bestDiffIdx else { return nil }

    let orig = origTokens[i]
    let repl = curTokens[start + i]

    // D-02: reject <= 2 chars or digits-only
    let digitsOnly = CharacterSet.decimalDigits
    guard orig.count > 2, repl.count > 2,
          !orig.unicodeScalars.allSatisfy({ digitsOnly.contains($0) }),
          !repl.unicodeScalars.allSatisfy({ digitsOnly.contains($0) }) else { return nil }

    return (orig, repl)
}

// MARK: - Window slicing

extension String {
    /// Slice self to a symmetric window of `radius` chars centered on `center`.
    /// Bounds-safe; returns self unchanged if radius >= count.
    func windowSlice(around center: Int, radius: Int) -> String {
        guard count > radius * 2 else { return self }
        let lo = max(0, center - radius)
        let hi = min(count, center + radius)
        let start = index(startIndex, offsetBy: lo)
        let end   = index(startIndex, offsetBy: hi)
        return String(self[start..<end])
    }
}
