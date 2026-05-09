import XCTest
@testable import ListenToMe

/// Pure-logic tests for `PartialTranscriber.filterHallucination` —
/// the gate that drops common whisper-on-silence outputs before they
/// land in `AppState.partialText`. The polling loop itself is timing-
/// and audio-driven (lives MainActor + WhisperLib + AudioRecorder)
/// and is exercised manually in the running app; these tests cover
/// the filter rules that decide what the user actually sees.
final class PartialTranscriberTests: XCTestCase {

    // MARK: - Hallucination filter

    func test_filter_drops_blank_audio_marker() {
        XCTAssertEqual(PartialTranscriber.filterHallucination("[BLANK_AUDIO]"), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("[blank_audio]"), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination(" [BLANK_AUDIO] \n"), "")
    }

    func test_filter_drops_silence_markers() {
        XCTAssertEqual(PartialTranscriber.filterHallucination("[SILENCE]"), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("(silence)"), "")
    }

    func test_filter_drops_music_markers() {
        XCTAssertEqual(PartialTranscriber.filterHallucination("[MUSIC]"), "")
    }

    func test_filter_drops_thank_you_hallucination() {
        // Whisper renders many silences as "Thank you." — a known
        // training-data artifact.
        XCTAssertEqual(PartialTranscriber.filterHallucination("Thank you."), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("thank you"), "")
    }

    func test_filter_drops_single_word_you() {
        XCTAssertEqual(PartialTranscriber.filterHallucination("you"), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("You"), "")
    }

    func test_filter_drops_pure_punctuation() {
        XCTAssertEqual(PartialTranscriber.filterHallucination("."), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("..."), "")
    }

    func test_filter_drops_empty_or_whitespace() {
        XCTAssertEqual(PartialTranscriber.filterHallucination(""), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("   "), "")
        XCTAssertEqual(PartialTranscriber.filterHallucination("\n\n"), "")
    }

    // MARK: - Pass-through

    func test_filter_passes_real_partials() {
        let real = "I'm dictating right now into the pill"
        XCTAssertEqual(PartialTranscriber.filterHallucination(real), real)
    }

    func test_filter_trims_whitespace_around_real_text() {
        XCTAssertEqual(
            PartialTranscriber.filterHallucination("  Hello world  \n"),
            "Hello world"
        )
    }

    func test_filter_does_not_drop_text_containing_thank_you() {
        // Only an EXACT match drops; "thank you for that" stays.
        let real = "thank you for that report"
        XCTAssertEqual(PartialTranscriber.filterHallucination(real), real)
    }

    func test_filter_does_not_drop_long_partial_starting_with_you() {
        let real = "you should send the report"
        XCTAssertEqual(PartialTranscriber.filterHallucination(real), real)
    }
}

/// Tests for the `Preferences.streamingPartialsEnabled` toggle wiring.
final class StreamingPartialsPrefTests: XCTestCase {

    private static let key = "wf.streamingPartialsEnabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        super.tearDown()
    }

    func test_default_is_off() {
        // Off by default — partial passes have hallucination + battery
        // tradeoffs; user should opt in deliberately.
        XCTAssertFalse(Preferences.shared.streamingPartialsEnabled)
    }

    func test_persists_across_reads() {
        Preferences.shared.streamingPartialsEnabled = true
        XCTAssertTrue(Preferences.shared.streamingPartialsEnabled)
        Preferences.shared.streamingPartialsEnabled = false
        XCTAssertFalse(Preferences.shared.streamingPartialsEnabled)
    }
}
