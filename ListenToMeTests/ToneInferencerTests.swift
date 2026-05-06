import XCTest
@testable import ListenToMe

/// Pure-logic tests for `ToneInferencer.infer(samples:)` — the Phase 4
/// deterministic 5-tone rubric. Locks the categorical thresholds so a
/// later refactor or rubric retune doesn't silently flip behaviour.
final class ToneInferencerTests: XCTestCase {

    func test_infer_returnsNoneBelowMinSamples() {
        // Rubric requires 20+ samples; below that → .none always.
        let samples = (0..<19).map { _ in "Some short message." }
        XCTAssertEqual(ToneInferencer.infer(samples: samples), .none)
    }

    func test_infer_detectsCodeWhenFencesPresent() {
        // ≥20% of samples containing ``` triggers .code.
        var samples = (0..<10).map { _ in "regular text" }
        samples.append(contentsOf: (0..<10).map { _ in "```swift\nlet x = 1\n```" })
        XCTAssertEqual(ToneInferencer.infer(samples: samples), .code)
    }

    func test_infer_detectsMarkdownWhenSyntaxPresent() {
        // ≥30% of samples with markdown syntax triggers .markdown.
        var samples = (0..<10).map { _ in "plain line" }
        samples.append(contentsOf: (0..<10).map { _ in "# Heading\n- bullet" })
        XCTAssertEqual(ToneInferencer.infer(samples: samples), .markdown)
    }

    func test_infer_detectsCasualFromContractionsAndShortSentences() {
        // High contraction rate + short avg sentence length → .casual.
        let samples = Array(repeating: "I'm gonna go. Can't wait!", count: 25)
        XCTAssertEqual(ToneInferencer.infer(samples: samples), .casual)
    }

    func test_infer_detectsFormalFromLongSentencesAndFormalLex() {
        // Long sentences + formal lexicon hits, no first-person, no
        // contractions → .formal. (The casual-branch firstPerson trigger
        // fires at >=4 per 100 words, so the sample studiously avoids
        // first-person pronouns.)
        let s = "The committee shall furthermore review and accordingly publish the relevant amendments hereby noted whereby compliance pursuant to the policy is required."
        let samples = Array(repeating: s, count: 25)
        XCTAssertEqual(ToneInferencer.infer(samples: samples), .formal)
    }

    func test_infer_returnsNoneWhenNoClauseTrips() {
        // Neutral middle-of-the-road text — long enough sentences to escape
        // the casual `avgSentLen <= 10` trigger, no formal lexicon, no
        // first-person, no contractions → falls through every clause.
        let s = "The weather forecast suggested moderate cloud coverage throughout the morning along with steady temperatures across the central region today."
        let samples = Array(repeating: s, count: 25)
        XCTAssertEqual(ToneInferencer.infer(samples: samples), .none)
    }
}
