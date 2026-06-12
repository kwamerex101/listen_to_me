import XCTest
@testable import ListenToMe

/// Pure-logic tests for the benchmark's WER metric.
final class WERCalculatorTests: XCTestCase {

    func test_identical_is_zero() {
        XCTAssertEqual(WERCalculator.wer(reference: "the cat sat", hypothesis: "the cat sat"), 0.0)
    }

    func test_case_and_punctuation_ignored() {
        XCTAssertEqual(WERCalculator.wer(reference: "The meeting is at three PM.",
                                         hypothesis: "the meeting is at three pm"), 0.0)
    }

    func test_digit_normalization() {
        // "3 PM" vs "three PM" must not count as an error.
        XCTAssertEqual(WERCalculator.wer(reference: "the meeting is at three PM",
                                         hypothesis: "The meeting is at 3 PM."), 0.0)
    }

    func test_one_substitution() {
        // 1 error over 4 reference words.
        XCTAssertEqual(WERCalculator.wer(reference: "send the report monday",
                                         hypothesis: "send the report tuesday"),
                       0.25, accuracy: 0.0001)
    }

    func test_deletion_and_insertion() {
        // ref 4 words; hyp drops one (deletion) → 1/4.
        XCTAssertEqual(WERCalculator.wer(reference: "please send the report",
                                         hypothesis: "send the report"),
                       0.25, accuracy: 0.0001)
        // hyp adds one (insertion) → 1/4.
        XCTAssertEqual(WERCalculator.wer(reference: "send the report",
                                         hypothesis: "please send the report"),
                       1.0 / 3.0, accuracy: 0.0001)
    }

    func test_contractions_normalized() {
        XCTAssertEqual(WERCalculator.wer(reference: "don't worry", hypothesis: "dont worry"), 0.0)
    }

    func test_empty_reference() {
        XCTAssertEqual(WERCalculator.wer(reference: "", hypothesis: ""), 0.0)
        XCTAssertEqual(WERCalculator.wer(reference: "", hypothesis: "noise"), 1.0)
    }

    func test_total_miss_is_full_error() {
        XCTAssertEqual(WERCalculator.wer(reference: "alpha beta", hypothesis: "gamma delta"), 1.0)
    }

    // MARK: - presentation normalization (benchmark artifacts)

    func test_pm_abbreviation_not_an_error() {
        // "3 p.m." must equal "three PM" — formatting, not a mishear.
        XCTAssertEqual(WERCalculator.wer(
            reference: "The meeting is scheduled for three PM on Tuesday afternoon.",
            hypothesis: "The meeting is scheduled for 3 p.m. on Tuesday afternoon."), 0.0)
    }

    func test_british_spelling_not_an_error() {
        XCTAssertEqual(WERCalculator.wer(
            reference: "Their team knew the route through the harbor would take two hours.",
            hypothesis: "Their team knew the route through the harbour would take two hours."), 0.0)
    }

    func test_real_error_still_counts_amid_spelling_normalization() {
        // "routes" vs "route" is a real ASR slip → still 1 error of 12.
        XCTAssertEqual(WERCalculator.wer(
            reference: "Their team knew the route through the harbor would take two hours.",
            hypothesis: "Their team knew the routes through the harbour would take two hours."),
            1.0 / 12.0, accuracy: 0.0001)
    }
}
