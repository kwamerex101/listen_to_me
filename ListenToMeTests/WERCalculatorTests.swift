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
}
