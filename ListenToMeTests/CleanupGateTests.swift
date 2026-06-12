import XCTest
@testable import ListenToMe

/// Tests for the messiness-aware cleanup gate. Pure logic, no model.
final class CleanupGateTests: XCTestCase {

    // MARK: - isAlreadyClean

    func test_clean_sentence_is_clean() {
        XCTAssertTrue(CleanupGate.isAlreadyClean("The meeting is at 3 PM on Tuesday."))
    }

    func test_filler_makes_it_messy() {
        XCTAssertFalse(CleanupGate.isAlreadyClean("Um, the meeting is at 3 PM."))
    }

    func test_stutter_makes_it_messy() {
        XCTAssertFalse(CleanupGate.isAlreadyClean("The the meeting is at 3 PM."))
    }

    func test_missing_terminal_punctuation_is_messy() {
        XCTAssertFalse(CleanupGate.isAlreadyClean("the meeting is at 3 PM"))
    }

    func test_lowercase_start_is_messy() {
        XCTAssertFalse(CleanupGate.isAlreadyClean("the meeting is at 3 PM."))
    }

    func test_question_mark_counts_as_terminal() {
        XCTAssertTrue(CleanupGate.isAlreadyClean("Are we still on for Tuesday?"))
    }

    func test_empty_is_clean() {
        XCTAssertTrue(CleanupGate.isAlreadyClean("   "))
    }

    // MARK: - shouldClean (mode interplay)

    func test_off_never_cleans() {
        XCTAssertFalse(CleanupGate.shouldClean(text: "um the the mess", wordCount: 100, mode: .off))
    }

    func test_always_cleans_even_clean_text() {
        // .always is explicit — respected verbatim, even for clean text.
        XCTAssertTrue(CleanupGate.shouldClean(text: "All good.", wordCount: 2, mode: .always))
    }

    func test_smart_skips_clean_text_above_threshold() {
        // 25 words > smart20 threshold, but the text is already clean → skip.
        let clean = "This is a perfectly clean sentence that runs well past the twenty word " +
                    "threshold and needs absolutely no cleanup at all today."
        XCTAssertGreaterThan(clean.split(separator: " ").count, 20)
        XCTAssertFalse(CleanupGate.shouldClean(text: clean, wordCount: 25, mode: .smart20))
    }

    func test_smart_cleans_messy_text_above_threshold() {
        let messy = "um so like this this is a a messy transcript with fillers and stutters " +
                    "that definitely needs cleaning up past the twenty word threshold"
        XCTAssertTrue(CleanupGate.shouldClean(text: messy, wordCount: 25, mode: .smart20))
    }

    func test_smart_skips_below_threshold() {
        XCTAssertFalse(CleanupGate.shouldClean(text: "um messy", wordCount: 2, mode: .smart20))
    }
}
