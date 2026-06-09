import XCTest
@testable import ListenToMe

/// Pure-logic tests for `WhisperLib.joinSegments` — the gap-to-paragraph
/// rule applied to the final transcription pass. Timestamps are
/// centiseconds (10 ms units); the threshold is 150 (1.5 s).
@MainActor
final class WhisperSegmentJoinTests: XCTestCase {

    private typealias Segment = (text: String, t0: Int64, t1: Int64)

    func test_empty_segments_yield_empty_string() {
        XCTAssertEqual(WhisperLib.joinSegments([], paragraphBreaks: true), "")
    }

    func test_single_segment_passes_through_trimmed() {
        let segs: [Segment] = [(" Hello world. ", 0, 200)]
        XCTAssertEqual(WhisperLib.joinSegments(segs, paragraphBreaks: true), "Hello world.")
    }

    func test_small_gap_joins_flat() {
        // 0.8 s gap — normal inter-sentence breathing, no break.
        let segs: [Segment] = [
            ("First sentence.", 0, 300),
            (" Second sentence.", 380, 600),
        ]
        XCTAssertEqual(WhisperLib.joinSegments(segs, paragraphBreaks: true),
                       "First sentence. Second sentence.")
    }

    func test_gap_at_threshold_inserts_paragraph_break() {
        // Exactly 1.5 s gap.
        let segs: [Segment] = [
            ("First paragraph.", 0, 300),
            (" Second paragraph.", 450, 700),
        ]
        XCTAssertEqual(WhisperLib.joinSegments(segs, paragraphBreaks: true),
                       "First paragraph.\n\nSecond paragraph.")
    }

    func test_long_gap_inserts_paragraph_break() {
        // 3 s gap.
        let segs: [Segment] = [
            ("Intro here.", 0, 200),
            (" Body starts now.", 500, 900),
        ]
        XCTAssertEqual(WhisperLib.joinSegments(segs, paragraphBreaks: true),
                       "Intro here.\n\nBody starts now.")
    }

    func test_breaks_disabled_join_flat_regardless_of_gap() {
        // Partial-preview path: paragraphBreaks false ignores even huge gaps.
        let segs: [Segment] = [
            ("First.", 0, 100),
            (" Second.", 2_000, 2_200),
        ]
        XCTAssertEqual(WhisperLib.joinSegments(segs, paragraphBreaks: false),
                       "First. Second.")
    }

    func test_multiple_gaps_produce_multiple_paragraphs() {
        let segs: [Segment] = [
            ("One.", 0, 100),
            (" Two.", 300, 400),     // 2 s gap → break
            (" Three.", 450, 550),   // 0.5 s gap → flat
            (" Four.", 800, 900),    // 2.5 s gap → break
        ]
        XCTAssertEqual(WhisperLib.joinSegments(segs, paragraphBreaks: true),
                       "One.\n\nTwo. Three.\n\nFour.")
    }
}
