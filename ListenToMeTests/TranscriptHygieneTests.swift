import XCTest
@testable import ListenToMe

/// Tests for `TranscriptHygiene.stripNonSpeechMarkers` — the filter that
/// removes engine-emitted non-speech artifacts ("[BLANK_AUDIO]", "[SILENCE]",
/// …) from the *final* transcript before it is pasted or stored in History.
///
/// Deliberately narrower than `PartialTranscriber.filterHallucination`: the
/// final path must keep legitimate short dictations like "you" / "thank you",
/// so only unambiguous bracketed/parenthesised markers are stripped.
final class TranscriptHygieneTests: XCTestCase {

    func test_strips_blank_audio_whole_utterance() {
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("[BLANK_AUDIO]"), "")
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers(" [BLANK_AUDIO] \n"), "")
    }

    func test_strips_case_insensitively() {
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("[blank_audio]"), "")
    }

    func test_strips_silence_and_music_markers() {
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("[SILENCE]"), "")
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("(silence)"), "")
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("[MUSIC]"), "")
    }

    func test_removes_embedded_marker_and_collapses_whitespace() {
        XCTAssertEqual(
            TranscriptHygiene.stripNonSpeechMarkers("Hello [BLANK_AUDIO] world"),
            "Hello world")
    }

    func test_preserves_real_transcript() {
        let real = "Let's ship the report on Monday."
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers(real), real)
    }

    func test_does_not_strip_thank_you_or_bare_you() {
        // Unlike the partial-preview filter, the final path must keep these —
        // they can be a genuine (if terse) dictation.
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("Thank you."), "Thank you.")
        XCTAssertEqual(TranscriptHygiene.stripNonSpeechMarkers("You"), "You")
    }
}
