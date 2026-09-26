import XCTest
@testable import ListenToMe

/// Tests for the negation- and number-preservation guard added to
/// `MeaningGuard`: a cleanup that drops a negator ("Do not deploy" →
/// "Deploy") or swaps a number ("15" → "50") leaves nearly every content
/// word intact, so the recall/hallucination/jaccard checks alone let it
/// through. These checks catch that failure mode directly.
final class MeaningGuardNegationTests: XCTestCase {

    // MARK: - Negation dropped → reject

    func test_rejects_negation_dropped_real_example() {
        let d = MeaningGuard.evaluate(
            cleaned: "Deploy the build to production tonight.",
            original: "Do not deploy the build to production tonight")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_accepts_dont_normalized_to_do_not() {
        let d = MeaningGuard.evaluate(
            cleaned: "Do not ship it yet.",
            original: "don't ship it yet")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_accepts_stutter_no_no_collapsed() {
        let d = MeaningGuard.evaluate(
            cleaned: "No, we won't.",
            original: "no no, we won't")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_negationCount_collapses_immediate_repeats() {
        XCTAssertEqual(MeaningGuard.negationCount("no no we won't"), 2)   // "no"(x1) + "not"
        XCTAssertEqual(MeaningGuard.negationCount("not not sure"), 1)
        XCTAssertEqual(MeaningGuard.negationCount("no, definitely no"), 2) // not adjacent -> both count
    }

    func test_negationCount_normalizes_contractions() {
        XCTAssertEqual(MeaningGuard.negationCount("cannot do it"), 1)
        XCTAssertEqual(MeaningGuard.negationCount("can't do it"), 1)
        XCTAssertEqual(MeaningGuard.negationCount("do it"), 0)
    }

    // MARK: - Numbers

    func test_rejects_number_flip_real_example() {
        let d = MeaningGuard.evaluate(cleaned: "There were 50 people.",
                                      original: "There were 15 people")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_accepts_number_word_promoted_to_digits() {
        // Cleanup may ADD numbers (spelled-out -> digits) without penalty.
        let d = MeaningGuard.evaluate(cleaned: "Bring 15 chairs.",
                                      original: "bring fifteen chairs")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_accepts_thousands_separator_normalized() {
        // Enough surrounding content words that the unrelated content-word
        // recall metric (which tokenizes "1,000" as two separate digit
        // groups) doesn't itself reject a too-short sentence — the point
        // here is specifically that the number-preservation check treats
        // "1,000" and "1000" as the same number.
        let d = MeaningGuard.evaluate(
            cleaned: "We have 1000 registered users in the system.",
            original: "we have 1,000 registered users in the system")
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_rejects_decimal_turned_into_different_integer() {
        let d = MeaningGuard.evaluate(cleaned: "The rate is 35 percent.",
                                      original: "the rate is 3.5 percent")
        XCTAssertFalse(d.isAccept, "\(d)")
    }

    func test_numbersPreserved_multisetContainment() {
        XCTAssertTrue(MeaningGuard.numbersPreserved(original: "1,000 users", cleaned: "1000 users"))
        XCTAssertFalse(MeaningGuard.numbersPreserved(original: "3.5", cleaned: "35"))
        XCTAssertTrue(MeaningGuard.numbersPreserved(original: "fifteen", cleaned: "15"))
        // A repeated number must survive the same number of times.
        XCTAssertTrue(MeaningGuard.numbersPreserved(original: "2 and 2", cleaned: "2, 2, and more"))
        XCTAssertFalse(MeaningGuard.numbersPreserved(original: "2 and 2", cleaned: "2 and 3"))
    }

    // MARK: - preserveNegationAndNumbers toggle

    func test_toggle_off_lets_negation_flip_through() {
        var thresholds = MeaningGuard.Thresholds.default
        thresholds.preserveNegationAndNumbers = false
        let d = MeaningGuard.evaluate(
            cleaned: "Ship it Friday.",
            original: "Don't ship it Friday.",
            thresholds: thresholds)
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_rewrite_path_accepts_polarity_flip_when_preserve_is_off() throws {
        // ClaudeClient.sanitizeRewrite explicitly disables preservation —
        // a Backtrack revision may legitimately flip "urgent" to "not
        // urgent" or change a date/number.
        let out = try ClaudeClient.sanitizeRewrite(
            output: "Don't ship it Friday.",
            original: "Ship it Friday.")
        XCTAssertEqual(out, "Don't ship it Friday.")
    }

    // MARK: - Transform thresholds accept a translation

    func test_transform_thresholds_accept_translation() {
        let d = MeaningGuard.evaluate(
            cleaned: "Bonjour, comment allez-vous aujourd'hui?",
            original: "Hello, how are you today?",
            thresholds: MeaningGuard.Thresholds.transform)
        XCTAssertTrue(d.isAccept, "\(d)")
    }

    func test_transform_thresholds_have_preservation_off() {
        XCTAssertFalse(MeaningGuard.Thresholds.transform.preserveNegationAndNumbers)
    }
}
