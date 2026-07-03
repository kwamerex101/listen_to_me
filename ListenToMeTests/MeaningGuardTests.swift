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

    // MARK: - Interrogative preservation

    func test_rejects_question_flattened_to_statement() {
        // Real failure from live data: a dictated question was silently
        // rewritten into a declarative claim. Content words survive, so the
        // recall/hallucination/length checks all pass — only the lost '?'
        // reveals the inverted intent.
        let d = MeaningGuard.evaluate(
            cleaned: "I can get all three options in a tabulated form so we can compare and contrast.",
            original: "Can we get all three options in a tabulated form, so we can compare and contrast?")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_accepts_question_that_stays_a_question() {
        let d = MeaningGuard.evaluate(
            cleaned: "Can we get all three options in a tabulated form?",
            original: "can we get all three options in a tabulated form?")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_accepts_statement_that_stays_a_statement() {
        // No question mark in the original → the interrogative guard must not
        // fire; a normal declarative cleanup still passes.
        let d = MeaningGuard.evaluate(
            cleaned: "We ship Monday.",
            original: "um we ship monday")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_identical_text_accepts() {
        let d = MeaningGuard.evaluate(cleaned: "ship the report monday",
                                      original: "ship the report monday")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    // MARK: - intensity thresholds

    func test_intensity_thresholds_loosen_monotonically() {
        let l = MeaningGuard.Thresholds.of(.light)
        let m = MeaningGuard.Thresholds.of(.medium)
        let h = MeaningGuard.Thresholds.of(.high)
        // Higher intensity = looser guard: min* non-increasing, max* non-decreasing.
        XCTAssertGreaterThanOrEqual(l.minRecall, m.minRecall)
        XCTAssertGreaterThanOrEqual(m.minRecall, h.minRecall)
        XCTAssertLessThanOrEqual(l.maxHallucination, m.maxHallucination)
        XCTAssertLessThanOrEqual(m.maxHallucination, h.maxHallucination)
        XCTAssertGreaterThanOrEqual(l.minJaccard, h.minJaccard)
        XCTAssertLessThanOrEqual(l.maxLengthRatio, h.maxLengthRatio)
    }

    func test_light_matches_defaults() {
        let l = MeaningGuard.Thresholds.of(.light)
        let d = MeaningGuard.Thresholds.default
        XCTAssertEqual(l.minRecall, d.minRecall)
        XCTAssertEqual(l.maxLengthRatio, d.maxLengthRatio)
    }
}
