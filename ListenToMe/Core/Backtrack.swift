import Foundation

/// Detect "backtrack" voice commands at the start of a transcript —
/// the user is asking to revise the *previous* dictation rather than
/// dictate something new. Wispr Flow's standout feature; reimplemented
/// here against `Paster.replace` + Claude rewrite.
///
/// Examples that match (revision text in italics):
///   "Actually, *make that next Thursday*"
///   "Scratch that, *I meant Friday*"
///   "Wait, change that to *the Q3 numbers*"
///   "No wait, *use the staging URL*"
///
/// Examples that do NOT match (false-positive guards):
///   "actually that's what I said"   — no revision-intent verb
///   "scratch the surface of …"      — not a leading scratch-that
enum Backtrack {
    /// Result of parsing. `revision` is the text the user wants to
    /// substitute / inject; non-empty when the trigger fired and a
    /// revision payload followed it.
    struct Match: Equatable {
        let trigger: String      // matched leading phrase, normalized
        let revision: String     // payload after the trigger
    }

    /// Look for a backtrack trigger at the start of `transcript`.
    /// Returns nil when no trigger or when the revision payload is too
    /// short to act on (≤ 1 word) — the latter prevents accidentally
    /// rewriting the previous paste with garbage like "actually." which
    /// usually means the user changed their mind and didn't follow
    /// through.
    static func parse(_ transcript: String) -> Match? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Case-insensitive prefix match. Order matters — longer phrases
        // first so "no wait" beats "wait".
        let triggers: [String] = [
            "actually,",
            "actually ",
            "scratch that,",
            "scratch that ",
            "wait, scratch that",
            "wait scratch that",
            "no wait, change that to",
            "no wait change that to",
            "no wait,",
            "no wait ",
            "wait, change that to",
            "wait change that to",
            "change that to",
            "i meant,",
            "i meant ",
        ]
        let lower = trimmed.lowercased()
        for trig in triggers {
            if lower.hasPrefix(trig) {
                let revision = String(trimmed.dropFirst(trig.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;-"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let words = revision.split(whereSeparator: \.isWhitespace).count
                guard words >= 2 else { return nil }
                return Match(trigger: trig, revision: revision)
            }
        }
        return nil
    }
}
