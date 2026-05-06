import XCTest
@testable import ListenToMe

/// Pure-logic tests for `VoiceEditor.apply` — the deterministic
/// transcript transformer that handles voice-editing tokens (comma,
/// period, scratch that, new paragraph, …) before cleanup.
final class VoiceEditorTests: XCTestCase {

    func test_apply_replacesSpokenComma() {
        // Auto-capitalizes the first letter (start-of-sentence rule).
        XCTAssertEqual(VoiceEditor.apply("hello comma world"), "Hello, world")
    }

    func test_apply_replacesSpokenPeriodAndCapitalizesNext() {
        let out = VoiceEditor.apply("first sentence period second sentence")
        XCTAssertTrue(out.contains("First sentence."))
        XCTAssertTrue(out.contains("Second sentence"))
    }

    func test_apply_questionMark() {
        let out = VoiceEditor.apply("really question mark")
        XCTAssertTrue(out.contains("Really?"))
    }

    func test_apply_exclamationPoint() {
        let out = VoiceEditor.apply("watch out exclamation point")
        XCTAssertTrue(out.contains("Watch out!"))
    }

    func test_apply_newParagraph() {
        let out = VoiceEditor.apply("first new paragraph second")
        XCTAssertTrue(out.contains("\n\n"))
    }

    func test_apply_scratchThat_dropsPriorSentence() {
        // "scratch that" wipes the most recent sentence.
        let out = VoiceEditor.apply("hello world period bye scratch that")
        XCTAssertFalse(out.lowercased().contains("bye"))
    }

    func test_apply_pureScratchProducesEmpty() {
        // Edge case the pipeline relies on: pure-undo dictation.
        let out = VoiceEditor.apply("scratch that")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func test_apply_passesThroughBenignText_capitalizingFirstLetter() {
        XCTAssertEqual(VoiceEditor.apply("plain text"), "Plain text")
    }
}
