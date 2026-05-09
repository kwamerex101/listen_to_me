import XCTest
@testable import ListenToMe

/// Round-trip and edge-case tests for the NDJSON encode/decode pair
/// that backs HistoryStore. Drives the static helpers directly against
/// a temp-dir URL so we can validate without standing up the
/// MainActor-isolated singleton (which would touch the user's real
/// Application Support directory).
final class HistoryStoreNDJSONTests: XCTestCase {

    private var tmpURL: URL!

    override func setUp() {
        super.setUp()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-test-\(UUID().uuidString).ndjson")
    }

    override func tearDown() {
        if let url = tmpURL { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    // MARK: - Round-trip

    func test_roundTrip_preserves_records() {
        let records = makeRecords(count: 3)
        HistoryStore.writeAll(records, to: tmpURL)

        let raw = try! Data(contentsOf: tmpURL)
        // Parsed order is chronological-on-disk (oldest first); the
        // store reverses on load to put newest-first in memory. We
        // verify the on-disk shape here and the reversal contract.
        let parsed = HistoryStore.parseNDJSON(raw)
        let restored = parsed.reversed()
        XCTAssertEqual(Array(restored).map(\.id), records.map(\.id))
        XCTAssertEqual(Array(restored).map(\.rawText), records.map(\.rawText))
        XCTAssertEqual(Array(restored).map(\.finalText), records.map(\.finalText))
    }

    func test_roundTrip_preserves_bundleId_optional() {
        let records: [TranscriptRecord] = [
            TranscriptRecord(id: UUID(), timestamp: Date(),
                             rawText: "a", finalText: "A",
                             durationMs: 1000, dismissed: false,
                             bundleId: "com.apple.mail"),
            TranscriptRecord(id: UUID(), timestamp: Date(),
                             rawText: "b", finalText: "B",
                             durationMs: 2000, dismissed: false,
                             bundleId: nil),
        ]
        HistoryStore.writeAll(records, to: tmpURL)
        let raw = try! Data(contentsOf: tmpURL)
        let parsed = Array(HistoryStore.parseNDJSON(raw).reversed())
        XCTAssertEqual(parsed[0].bundleId, "com.apple.mail")
        XCTAssertNil(parsed[1].bundleId)
    }

    func test_writeAll_produces_one_line_per_record_plus_trailing_newline() {
        let records = makeRecords(count: 5)
        HistoryStore.writeAll(records, to: tmpURL)
        let raw = try! Data(contentsOf: tmpURL)
        let lines = raw.split(separator: 0x0A, omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 5)
        // Last byte should be a newline (canonical NDJSON shape).
        XCTAssertEqual(raw.last, 0x0A)
    }

    func test_empty_snapshot_produces_empty_file() {
        HistoryStore.writeAll([], to: tmpURL)
        let raw = try! Data(contentsOf: tmpURL)
        XCTAssertEqual(raw.count, 0)
    }

    // MARK: - Partial recovery

    func test_parseNDJSON_skips_malformed_lines_keeps_valid_ones() {
        let valid = TranscriptRecord(id: UUID(), timestamp: Date(),
                                     rawText: "good", finalText: "Good.",
                                     durationMs: 100, dismissed: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var blob = Data()
        // line 1: garbage
        blob.append("this is not json\n".data(using: .utf8)!)
        // line 2: valid
        blob.append(try! encoder.encode(valid))
        blob.append(0x0A)
        // line 3: empty (omittingEmptySubsequences should skip)
        blob.append(0x0A)
        // line 4: garbage
        blob.append("{ truncated".data(using: .utf8)!)
        let parsed = HistoryStore.parseNDJSON(blob)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].id, valid.id)
        XCTAssertEqual(parsed[0].rawText, "good")
    }

    // MARK: - Decoder back-compat (records without bundleId)

    func test_decoder_reads_legacy_record_without_bundleId() {
        // Emulate an entry serialized before bundleId was added —
        // CodingKeys + decodeIfPresent should make this a clean nil.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","timestamp":"\(ISO8601DateFormatter().string(from: Date()))","rawText":"hi","finalText":"Hi.","durationMs":100,"dismissed":false}
        """
        var blob = Data()
        blob.append(legacyJSON.data(using: .utf8)!)
        blob.append(0x0A)
        let parsed = HistoryStore.parseNDJSON(blob)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNil(parsed[0].bundleId)
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
