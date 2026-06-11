import XCTest
@testable import ListenToMe

/// Pure-logic tests for the cleanup metrics (no model). These pin the
/// behaviour the eval harness and the meaning-guard both rely on.
final class CleanupMetricsTests: XCTestCase {

    // MARK: - contentWords

    func test_contentWords_drops_fillers_and_stopwords() {
        // "um", "like", "the", "i" all dropped; content survives.
        let words = CleanupMetrics.contentWords("um I like the red car")
        XCTAssertEqual(words, ["red", "car"])
    }

    func test_contentWords_normalizes_contractions() {
        // apostrophe removed, word kept contiguous — "don't" → "dont".
        let words = CleanupMetrics.contentWords("don't worry")
        XCTAssertEqual(words, ["dont", "worry"])
    }

    func test_contentWords_lowercases_and_splits_punctuation() {
        XCTAssertEqual(CleanupMetrics.contentWords("Ship Monday, please!"),
                       ["ship", "monday", "please"])
    }

    // MARK: - recall

    func test_recall_full_when_content_preserved() {
        // Filler removal + punctuation must not cost recall.
        let r = CleanupMetrics.contentWordRecall(
            candidate: "We ship Monday.",
            reference: "um we ship monday")
        XCTAssertEqual(r, 1.0, accuracy: 0.0001)
    }

    func test_recall_drops_when_content_word_lost() {
        // reference content = {ship, monday, report}; candidate lost "report".
        let r = CleanupMetrics.contentWordRecall(
            candidate: "Ship Monday.",
            reference: "ship the monday report")
        XCTAssertEqual(r, 2.0 / 3.0, accuracy: 0.0001)
    }

    func test_recall_empty_reference_is_one() {
        XCTAssertEqual(CleanupMetrics.contentWordRecall(candidate: "x", reference: ""), 1.0)
    }

    // MARK: - hallucination

    func test_hallucination_zero_when_all_words_from_raw() {
        let h = CleanupMetrics.hallucinationRate(
            candidate: "We ship Monday.",
            raw: "um we ship monday")
        XCTAssertEqual(h, 0.0, accuracy: 0.0001)
    }

    func test_hallucination_flags_invented_content() {
        // "tuesday" appears in neither raw nor reference → invented.
        let h = CleanupMetrics.hallucinationRate(
            candidate: "ship tuesday",
            raw: "ship monday")
        XCTAssertEqual(h, 0.5, accuracy: 0.0001)   // 1 of 2 content words invented
    }

    func test_hallucination_allows_reference_words() {
        let h = CleanupMetrics.hallucinationRate(
            candidate: "ship the report",
            raw: "ship",
            reference: "ship report")
        XCTAssertEqual(h, 0.0, accuracy: 0.0001)
    }

    // MARK: - jaccard / lengthRatio

    func test_jaccard_identical_content_is_one() {
        XCTAssertEqual(CleanupMetrics.contentJaccard("um ship monday", "Ship Monday."),
                       1.0, accuracy: 0.0001)
    }

    func test_jaccard_partial_overlap() {
        // {ship,monday} vs {ship,tuesday} → inter 1, union 3.
        XCTAssertEqual(CleanupMetrics.contentJaccard("ship monday", "ship tuesday"),
                       1.0 / 3.0, accuracy: 0.0001)
    }

    func test_lengthRatio_drops_with_filler_removal() {
        // 5 raw words → 3 kept = 0.6.
        let r = CleanupMetrics.lengthRatio(candidate: "we ship monday", raw: "um we like ship monday")
        XCTAssertEqual(r, 0.6, accuracy: 0.0001)
    }

    func test_lengthRatio_empty_raw() {
        XCTAssertEqual(CleanupMetrics.lengthRatio(candidate: "", raw: ""), 1.0)
    }
}
