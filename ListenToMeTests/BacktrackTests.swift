import XCTest
@testable import ListenToMe

/// Pure-logic tests for `Backtrack.parse` — the leading-trigger
/// detector that decides whether a fresh transcript is a revision of
/// the prior paste rather than new dictation. False positives here
/// would silently rewrite the user's last paste with garbage; false
/// negatives just mean the backtrack feature didn't fire.
final class BacktrackTests: XCTestCase {

    // MARK: - Positive matches

    func test_actually_comma_matches() {
        let m = Backtrack.parse("Actually, make that next Thursday")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "make that next Thursday")
    }

    func test_actually_no_comma_matches() {
        let m = Backtrack.parse("actually make that next Thursday")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "make that next Thursday")
    }

    func test_scratch_that_matches() {
        let m = Backtrack.parse("Scratch that, I meant Friday")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "I meant Friday")
    }

    func test_no_wait_change_that_to_matches() {
        let m = Backtrack.parse("No wait, change that to the staging URL")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "the staging URL")
    }

    func test_change_that_to_alone_matches() {
        let m = Backtrack.parse("Change that to the production URL")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "the production URL")
    }

    func test_i_meant_matches() {
        let m = Backtrack.parse("I meant Friday afternoon")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "Friday afternoon")
    }

    func test_wait_scratch_that_matches() {
        let m = Backtrack.parse("wait scratch that I meant the second one")
        XCTAssertNotNil(m)
        // Trigger consumed; revision is what's left.
        XCTAssertTrue(m!.revision.lowercased().contains("second one"))
    }

    func test_case_insensitive_at_start() {
        XCTAssertNotNil(Backtrack.parse("ACTUALLY, lower it to ten"))
        XCTAssertNotNil(Backtrack.parse("aCtUaLly make that twelve"))
    }

    func test_leading_whitespace_is_tolerated() {
        let m = Backtrack.parse("   actually use Tuesday instead")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.revision, "use Tuesday instead")
    }

    // MARK: - False-positive guards

    func test_payload_too_short_rejected() {
        // "actually." is the user trailing off; one-word payload "okay" is not a revision.
        XCTAssertNil(Backtrack.parse("actually okay"))
        XCTAssertNil(Backtrack.parse("actually."))
        XCTAssertNil(Backtrack.parse("scratch that done"))
    }

    func test_no_trigger_returns_nil() {
        XCTAssertNil(Backtrack.parse("just a normal sentence here"))
        XCTAssertNil(Backtrack.parse("the report is ready for review"))
    }

    func test_trigger_word_in_middle_does_not_match() {
        // "actually" must be at the start, not buried mid-sentence.
        XCTAssertNil(Backtrack.parse("the report is actually due next week"))
    }

    func test_empty_input_returns_nil() {
        XCTAssertNil(Backtrack.parse(""))
        XCTAssertNil(Backtrack.parse("   "))
    }

    // MARK: - Trigger boundary

    func test_revision_strips_trailing_punctuation_from_payload_start() {
        // "Actually, ,X" should not leave a stray comma at the start.
        let m = Backtrack.parse("Actually, , next Thursday works better")
        XCTAssertNotNil(m)
        XCTAssertFalse(m!.revision.hasPrefix(","))
        XCTAssertTrue(m!.revision.contains("next Thursday"))
    }

    func test_match_returns_normalized_trigger() {
        let m = Backtrack.parse("actually move it forward by a day")
        XCTAssertNotNil(m)
        // Trigger field exists for downstream telemetry / debugging.
        XCTAssertFalse(m!.trigger.isEmpty)
    }
}
