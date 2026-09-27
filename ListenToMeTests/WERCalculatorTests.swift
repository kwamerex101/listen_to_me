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

    // MARK: - glued digit + am/pm ("3pm") normalization

    func test_glued_digit_ampm_forms_all_equal_three_pm() {
        let expected = WERCalculator.normalize("three pm")
        XCTAssertEqual(WERCalculator.normalize("3pm"), expected)
        XCTAssertEqual(WERCalculator.normalize("3 PM"), expected)
        XCTAssertEqual(WERCalculator.normalize("3:00pm"), expected)
        XCTAssertEqual(WERCalculator.normalize("3:00 p.m."), expected)
    }

    func test_glued_digit_ampm_splits_into_number_and_marker() {
        XCTAssertEqual(WERCalculator.normalize("10am"), ["ten", "am"])
    }

    func test_glued_digit_ampm_not_an_error_end_to_end() {
        XCTAssertEqual(WERCalculator.wer(
            reference: "The meeting is scheduled for three PM on Tuesday afternoon.",
            hypothesis: "The meeting is scheduled for 3pm on Tuesday afternoon."), 0.0)
    }

    // MARK: - errorCount (pooled WER building block)

    func test_errorCount_matches_wer_for_a_single_card() {
        let (errors, words) = WERCalculator.errorCount(
            reference: "send the report monday", hypothesis: "send the report tuesday")
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(words, 4)
    }

    func test_errorCount_empty_reference() {
        XCTAssertEqual(WERCalculator.errorCount(reference: "", hypothesis: "").errors, 0)
        XCTAssertEqual(WERCalculator.errorCount(reference: "", hypothesis: "").referenceWords, 0)
        XCTAssertEqual(WERCalculator.errorCount(reference: "", hypothesis: "noise").errors, 1)
    }

    func test_pooled_aggregate_is_not_a_mean_of_percentages() {
        // Card A: 1 error / 10 words (10%). Card B: 3 errors / 20 words (15%).
        // Pooled: 4 errors / 30 words ≈ 13.3%, not the mean (12.5%) of the two.
        let a = WERCalculator.errorCount(
            reference: "one two three four five six seven eight nine ten",
            hypothesis: "one two three four five six seven eight nine wrong")
        let b = WERCalculator.errorCount(
            reference: "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango",
            hypothesis: "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec wrong wrong wrong")
        XCTAssertEqual(a.errors, 1)
        XCTAssertEqual(a.referenceWords, 10)
        XCTAssertEqual(b.errors, 3)
        XCTAssertEqual(b.referenceWords, 20)

        let pooledErrors = a.errors + b.errors
        let pooledWords = a.referenceWords + b.referenceWords
        let pooledWER = Double(pooledErrors) / Double(pooledWords)
        XCTAssertEqual(pooledWER, 4.0 / 30.0, accuracy: 0.0001)
        XCTAssertNotEqual(pooledWER, ((1.0 / 10.0) + (3.0 / 20.0)) / 2.0, accuracy: 0.0001)
    }

    func test_emptyHypothesis_countsEveryReferenceWordAsDeleted() {
        let (errors, words) = WERCalculator.errorCount(reference: "send the report", hypothesis: "")
        XCTAssertEqual(errors, 3)
        XCTAssertEqual(words, 3)
        XCTAssertEqual(WERCalculator.wer(reference: "send the report", hypothesis: ""), 1.0)
    }
}
