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

/// Returns (original_token, replacement_token) if exactly one word position
/// differs between `original` and `current`, both tokens pass the D-02
/// length/digit filter, and token counts are equal (D-01, D-11).
/// Case-sensitive (D-12). Returns nil on any violation.
func singleWordSwap(from original: String, to current: String) -> (String, String)? {
    let origTokens = tokenize(original)
    let currTokens = tokenize(current)
    guard origTokens.count == currTokens.count, !origTokens.isEmpty else { return nil }

    var diffIdx: Int? = nil
    for i in origTokens.indices {
        if origTokens[i] != currTokens[i] {
            guard diffIdx == nil else { return nil }  // more than one diff
            diffIdx = i
        }
    }
    guard let i = diffIdx else { return nil }  // identical — nothing to learn

    let orig = origTokens[i]
    let repl = currTokens[i]

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
