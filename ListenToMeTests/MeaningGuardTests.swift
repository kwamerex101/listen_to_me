import XCTest
@testable import ListenToMe

/// Tests for the meaning-preservation guard. Pure logic, no model.
final class MeaningGuardTests: XCTestCase {

    func test_accepts_filler_removal_and_punctuation() {
        let d = MeaningGuard.evaluate(
            cleaned: "We ship Monday.",
            original: "um we like ship monday you know")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_accepts_single_proper_noun_fix() {
        // One spelling fix among several content words must NOT be rejected.
        let d = MeaningGuard.evaluate(
            cleaned: "Send the report to Danquah on Friday.",
            original: "send the report to danqua on friday")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_rejects_bulk_hallucination_expansion() {
        let d = MeaningGuard.evaluate(
            cleaned: "Once upon a time the cat sat on the mat by the fire.",
            original: "the cat")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_rejects_total_rewrite() {
        // Completely different content words → low recall + high hallucination.
        let d = MeaningGuard.evaluate(
            cleaned: "The quarterly budget needs approval.",
            original: "remember to buy milk and eggs")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_rejects_major_content_loss() {
        // Dropped most content words.
        let d = MeaningGuard.evaluate(
            cleaned: "Meeting.",
            original: "schedule the budget meeting with finance and legal teams tomorrow")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_empty_original_accepts() {
        XCTAssertTrue(MeaningGuard.evaluate(cleaned: "anything", original: "   ").isAccept)
    }

    func test_identical_text_accepts() {
        let d = MeaningGuard.evaluate(cleaned: "ship the report monday",
                                      original: "ship the report monday")
        XCTAssertTrue(d.isAccept, "\(d)")
    }
}
