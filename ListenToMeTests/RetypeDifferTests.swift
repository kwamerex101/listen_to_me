import XCTest
@testable import ListenToMe

/// Pure-logic tests for `RetypeDiffer.singleWordSwap`. The function powers
/// the Phase 3 auto-learn-dictionary capture; if it regresses, every
/// candidate detection breaks silently. These tests pin the contract.
final class RetypeDifferTests: XCTestCase {

    func test_singleWordSwap_capturesOneTokenDiff_whenAligned() {
        let result = singleWordSwap(
            from: "I have successfully matched",
            to:   "I have successfully merged"
        )
        XCTAssertEqual(result?.0, "matched")
        XCTAssertEqual(result?.1, "merged")
    }

    func test_singleWordSwap_acceptsSlidingWindowMatchInNoisyField() {
        // A real-world Notes paste pattern — pre-existing paragraphs around
        // the dictation. The sliding-window form must find the unique
        // 1-diff window and ignore the noise.
        let result = singleWordSwap(
            from: "I have successfully matched",
            to:   "remotion remotion for videos I have successfully merged"
        )
        XCTAssertEqual(result?.0, "matched")
        XCTAssertEqual(result?.1, "merged")
    }

    func test_singleWordSwap_rejectsTwoDiffs() {
        // Two tokens differ → ambiguous, reject.
        let result = singleWordSwap(
            from: "I have been able to match successfully",
            to:   "i have been able to merge successfully"
        )
        XCTAssertNil(result)
    }

    func test_singleWordSwap_rejectsShortTokens() {
        // D-02: tokens ≤ 2 chars rejected — too noisy to learn from.
        let result = singleWordSwap(from: "I am a fan", to: "I am ok fan")
        XCTAssertNil(result)
    }

    func test_singleWordSwap_rejectsDigitsOnly() {
        let result = singleWordSwap(from: "Call me at 1234", to: "Call me at 5678")
        XCTAssertNil(result)
    }

    func test_singleWordSwap_returnsNilWhenIdentical() {
        let result = singleWordSwap(from: "no change here", to: "no change here")
        XCTAssertNil(result)
    }

    func test_singleWordSwap_isCaseSensitive_byD12() {
        // D-12: case-sensitive. "let" vs "Let" is a valid 1-token swap,
        // and both pass the >2-char D-02 filter — so the differ DOES
        // capture it. This pins the contract: case differences ARE
        // legitimate corrections to learn from.
        let result = singleWordSwap(from: "let me try this", to: "Let me try this")
        XCTAssertEqual(result?.0, "let")
        XCTAssertEqual(result?.1, "Let")
    }

    func test_singleWordSwap_rejectsAmbiguousMultipleWindows() {
        // Two equally-valid 1-diff windows → ambiguous, reject.
        let result = singleWordSwap(
            from: "alpha beta gamma",
            to:   "alpha beta delta alpha beta gamma alpha beta sigma"
        )
        // We can't know which swap to learn — tool stays silent.
        XCTAssertNil(result)
    }

    func test_tokenize_handlesPunctuation() {
        // `String.enumerateSubstrings(.byWords)` strips trailing punctuation.
        XCTAssertEqual(tokenize("Hello, world!"), ["Hello", "world"])
    }

    func test_tokenize_handlesEmpty() {
        XCTAssertEqual(tokenize(""), [])
    }
}
