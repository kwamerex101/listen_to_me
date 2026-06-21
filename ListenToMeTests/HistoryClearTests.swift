import XCTest
@testable import ListenToMe

/// Tests for the clearAll() history-wipe feature.
///
/// HistoryStore is a @MainActor singleton that writes to Application Support;
/// we cannot instantiate a fresh isolated copy. Instead we follow the same
/// pattern as HistoryStoreNDJSONTests: test the static read/write helpers
/// directly against a temp URL, and use MainActor.run to verify the
/// singleton's in-memory state via clearAll() (which only touches the shared
/// file, so here we leave that to the static-helper coverage).
final class HistoryClearTests: XCTestCase {

    private var tmpURL: URL!

    override func setUp() {
        super.setUp()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-clear-test-\(UUID().uuidString).ndjson")
    }

    override func tearDown() {
        if let url = tmpURL { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    // MARK: - Static primitive: writeAll([]) truncates the file

    func test_writeAll_empty_truncates_file() throws {
        // Write some records first.
        let records = makeRecords(count: 4)
        HistoryStore.writeAll(records, to: tmpURL)
        let before = try Data(contentsOf: tmpURL)
        XCTAssertGreaterThan(before.count, 0, "precondition: file should have content")

        // Now clear — writeAll with empty snapshot should produce a zero-byte file.
        HistoryStore.writeAll([], to: tmpURL)
        let after = try Data(contentsOf: tmpURL)
        XCTAssertEqual(after.count, 0, "writeAll([]) must produce an empty file")
    }

    func test_parseNDJSON_on_empty_file_returns_empty_array() throws {
        HistoryStore.writeAll([], to: tmpURL)
        let raw = try Data(contentsOf: tmpURL)
        let parsed = HistoryStore.parseNDJSON(raw)
        XCTAssertTrue(parsed.isEmpty, "parsing an empty file must return []")
    }

    func test_writeAll_empty_then_repopulate_round_trips() throws {
        // Clear, then write new records — ensures the file can be reused
        // after a clear without corruption.
        let original = makeRecords(count: 3)
        HistoryStore.writeAll(original, to: tmpURL)
        HistoryStore.writeAll([], to: tmpURL)

        let fresh = makeRecords(count: 2)
        HistoryStore.writeAll(fresh, to: tmpURL)

        let raw = try Data(contentsOf: tmpURL)
        let parsed = HistoryStore.parseNDJSON(raw)
        // reversed() because writeAll stores oldest-first on disk.
        let restored = Array(parsed.reversed())
        XCTAssertEqual(restored.map(\.id), fresh.map(\.id))
    }

    // MARK: - Injected store: clearAll() wipes in-memory records + truncates temp file

    func test_clearAll_empties_injected_store() async throws {
        // Seed the temp file with NDJSON records so the store loads them.
        let records = makeRecords(count: 3)
        HistoryStore.writeAll(records, to: tmpURL)

        // Build an isolated store backed by the temp URL — never touches
        // HistoryStore.shared or ~/Library/Application Support/ListenToMe/.
        let store = await MainActor.run { HistoryStore(url: tmpURL) }

        await MainActor.run {
            XCTAssertEqual(store.records.count, 3, "precondition: store loaded seeded records")
            store.clearAll()
            XCTAssertTrue(store.records.isEmpty,
                          "clearAll() must empty the in-memory records array")
        }

        // On-disk file must also be empty (zero bytes or no records).
        let after = try Data(contentsOf: tmpURL)
        XCTAssertEqual(after.count, 0, "clearAll() must truncate the backing file to zero bytes")
    }

    // MARK: - Helpers

    private func makeRecords(count: Int) -> [TranscriptRecord] {
        (0..<count).map { i in
            TranscriptRecord(
                id: UUID(),
                timestamp: Date(timeIntervalSinceNow: -Double(count - i)),
                rawText: "raw \(i)",
                finalText: "Final \(i).",
                durationMs: 1000 + i * 100,
                dismissed: false,
                bundleId: i.isMultiple(of: 2) ? "com.apple.mail" : nil
            )
        }
    }
}
