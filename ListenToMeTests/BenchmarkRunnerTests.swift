import XCTest
@testable import ListenToMe

/// Pure-logic tests for the benchmark's aggregate math — pooled WER across
/// cards, not a mean of per-card percentages.
final class BenchmarkRunnerTests: XCTestCase {

    private func result(errors: Int, words: Int, seconds: Double = 1.0) -> EngineResult {
        EngineResult(transcript: "", modelName: "test", errors: errors, referenceWords: words, seconds: seconds)
    }

    func test_pooled_aggregate_sums_errors_and_words_not_mean_of_percentages() {
        // Card A: 1/10 errors (10%). Card B: 3/20 errors (15%).
        // Pooled: 4/30 ≈ 13.3%, not the mean of the two percentages (12.5%).
        let agg = BenchmarkRunner.pooledAggregate([
            result(errors: 1, words: 10),
            result(errors: 3, words: 20),
        ])
        XCTAssertNotNil(agg)
        XCTAssertEqual(agg!.wer, 4.0 / 30.0, accuracy: 0.0001)
    }

    func test_pooled_aggregate_latency_is_still_a_mean() {
        let agg = BenchmarkRunner.pooledAggregate([
            result(errors: 0, words: 10, seconds: 1.0),
            result(errors: 0, words: 10, seconds: 3.0),
        ])
        XCTAssertEqual(agg!.sec, 2.0, accuracy: 0.0001)
    }

    func test_pooled_aggregate_empty_is_nil() {
        XCTAssertNil(BenchmarkRunner.pooledAggregate([]))
    }

    func test_pooled_aggregate_zero_reference_words_is_zero_wer() {
        // Degenerate case: no reference words at all across any card.
        let agg = BenchmarkRunner.pooledAggregate([result(errors: 0, words: 0)])
        XCTAssertEqual(agg!.wer, 0.0)
    }
}
