import XCTest
@testable import ListenToMe

final class TranscriptReviewDraftTests: XCTestCase {
    private func record(id: UUID = UUID(), text: String, raw: String = "Original", dismissed: Bool = false) -> TranscriptRecord {
        TranscriptRecord(id: id, timestamp: Date(timeIntervalSince1970: 1), rawText: raw,
                         finalText: text, durationMs: 1000, dismissed: dismissed)
    }

    func testUntouchedDraftRefreshesWhenSameRecordChanges() {
        let original = record(text: "First")
        var draft = TranscriptReviewDraft(record: original)
        let changed = record(id: original.id, text: "Updated", raw: "Updated original")
        draft.synchronize(records: [changed])
        XCTAssertEqual(draft.text, "Updated")
        XCTAssertEqual(draft.source?.rawText, "Updated original")
        XCTAssertFalse(draft.sourceChanged)
    }

    func testExplicitDraftSurvivesSourceUpdateAndCanReload() {
        let original = record(text: "First")
        var draft = TranscriptReviewDraft(record: original)
        draft.text = "My edits"
        draft.synchronize(records: [record(id: original.id, text: "Updated")])
        XCTAssertEqual(draft.text, "My edits")
        XCTAssertTrue(draft.sourceChanged)
        draft.reloadSavedText()
        XCTAssertEqual(draft.text, "Updated")
        XCTAssertFalse(draft.sourceChanged)
    }

    func testRepeatedSynchronizationPreservesExplicitDraft() {
        let original = record(text: "First")
        var draft = TranscriptReviewDraft(record: original)
        draft.text = "My edits"
        draft.synchronize(records: [original])
        draft.synchronize(records: [original])
        XCTAssertEqual(draft.text, "My edits")
        XCTAssertFalse(draft.sourceChanged)
    }

    func testDeletedDismissedOrBlankSourceBecomesUnavailable() {
        let original = record(text: "First")
        for records in [[], [record(id: original.id, text: "First", dismissed: true)],
                        [record(id: original.id, text: " \n ")]] {
            var draft = TranscriptReviewDraft(record: original)
            draft.synchronize(records: records)
            XCTAssertNil(draft.source)
            XCTAssertEqual(draft.text, "First")
        }
    }

    func testOtherHistoryRecordDoesNotReplaceSelectedSource() {
        let original = record(text: "First")
        var draft = TranscriptReviewDraft(record: original)
        draft.synchronize(records: [record(text: "Another record"), original])
        XCTAssertEqual(draft.source?.id, original.id)
        XCTAssertEqual(draft.text, "First")
    }
}
