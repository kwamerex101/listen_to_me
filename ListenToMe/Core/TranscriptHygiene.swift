import Foundation

/// Removes whole-utterance non-speech artifacts that transcription engines
/// emit on silence or noise ("[BLANK_AUDIO]", "[SILENCE]", "[MUSIC]", …)
/// from the *final* transcript, before it is pasted into the target app or
/// written to History. Without this, a silent recording lands a literal
/// "[BLANK_AUDIO]" in the user's document and in their dictation history.
///
/// Deliberately distinct from `PartialTranscriber.filterHallucination`: that
/// gate also drops bare words like "you" / "thank you" / "." because a
/// transient live preview can safely swallow them. On the final path those
/// are legitimate short dictations and must survive — so this filter only
/// removes the unambiguous bracketed / parenthesised non-lexical markers.
enum TranscriptHygiene {

    /// Bracketed / parenthesised non-speech markers, matched case-insensitively.
    private static let markers = [
        "[BLANK_AUDIO]",
        "[SILENCE]",
        "(silence)",
        "[MUSIC]",
        "[INAUDIBLE]",
        "(inaudible)",
    ]

    /// Strip non-speech markers from a final transcript and normalise the
    /// whitespace their removal leaves behind (newlines are preserved).
    /// Returns "" when the transcript was nothing but markers — the caller
    /// then treats it exactly like an empty transcript.
    static func stripNonSpeechMarkers(_ text: String) -> String {
        var out = text
        for marker in markers {
            out = out.replacingOccurrences(
                of: marker, with: "", options: [.caseInsensitive])
        }
        // Collapse the horizontal-whitespace runs left by the removals, then
        // trim. Uses a regex so intentional line breaks are left intact.
        out = out.replacingOccurrences(
            of: "[ \\t]{2,}", with: " ", options: [.regularExpression])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
