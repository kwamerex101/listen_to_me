import XCTest
@testable import ListenToMe

/// Undo-after-delete support: `HistoryStore.restore(_:)`. Uses an isolated
/// store built with `init(url:)` on a temp file, never `.shared`.
@MainActor
final class HistoryRestoreTests: XCTestCase {

    private var tmpURL: URL!

    override func setUp() {
        super.setUp()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-restore-test-\(UUID().uuidString).ndjson")
    }

    override func tearDown() {
        if let url = tmpURL { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    private func record(_ text: String, at offset: TimeInterval) -> TranscriptRecord {
        TranscriptRecord(id: UUID(), timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
                         rawText: text, finalText: text, durationMs: 1200,
                         dismissed: false, bundleId: "com.example.app")
    }

    func test_restore_reinsertsAtSortedPositionWithSameFields() {
        let store = HistoryStore(url: tmpURL)
        let newest = record("c", at: 300)
        let middle = record("b", at: 200)
        let oldest = record("a", at: 100)
        store.restore(oldest)
        store.restore(newest)
        store.restore(middle)

        XCTAssertEqual(store.records.map(\.finalText), ["c", "b", "a"])
        XCTAssertEqual(store.records[1], middle)

        store.remove(id: middle.id)
        XCTAssertEqual(store.records.map(\.finalText), ["c", "a"])
        store.restore(middle)
        XCTAssertEqual(store.records, [newest, middle, oldest])
    }

    func test_restore_isNoOpForExistingId() {
        let store = HistoryStore(url: tmpURL)
        let r = record("x", at: 10)
        store.restore(r)
        store.restore(r)
        XCTAssertEqual(store.records.count, 1)
    }
}
