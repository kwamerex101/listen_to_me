import XCTest
@testable import ListenToMe

final class TranscriptReviewPolicyTests: XCTestCase {
    private func record(_ time: TimeInterval, text: String, dismissed: Bool = false) -> TranscriptRecord {
        TranscriptRecord(id: UUID(), timestamp: Date(timeIntervalSince1970: time),
                         rawText: text, finalText: text, durationMs: 1000, dismissed: dismissed)
    }

    func testLatestUsableRecordSkipsNewerDismissedAndBlankRecords() {
        let usable = record(10, text: "Keep this transcript")
        let records = [record(30, text: "Dismissed", dismissed: true), usable,
                       record(20, text: " \n "), record(5, text: "Older")]
        XCTAssertEqual(TranscriptReviewPolicy.latest(in: records)?.id, usable.id)
    }

    func testSelectionUsesTimestampInsteadOfArrayOrder() {
        let newest = record(50, text: "Latest transcript")
        let older = record(10, text: "Older transcript")
        XCTAssertEqual(TranscriptReviewPolicy.latest(in: [newest, older])?.id, newest.id)
        XCTAssertEqual(TranscriptReviewPolicy.latest(in: [older, newest])?.id, newest.id)
    }

    func testNoUsableHistoryDisablesRecovery() {
        XCTAssertNil(TranscriptReviewPolicy.latest(in: []))
        XCTAssertNil(TranscriptReviewPolicy.latest(in: [record(1, text: ""),
                        record(2, text: "Dismissed", dismissed: true)]))
    }

    func testReviewCannotInterruptLiveOrCorrectingDictation() {
        let blocked: [Phase] = [.recording, .transcribing, .cleaning,
                                .polishing(rawPreview: "Text"), .correcting,
                                .suggestion(bundleId: "editor", tone: .casual)]
        for phase in blocked {
            XCTAssertFalse(TranscriptReviewPolicy.allowsReview(in: phase))
        }
        let allowed: [Phase] = [.idle, .success(preview: "Text"), .error(message: "Error"), .noSpeech]
        for phase in allowed {
            XCTAssertTrue(TranscriptReviewPolicy.allowsReview(in: phase))
        }
    }
}
