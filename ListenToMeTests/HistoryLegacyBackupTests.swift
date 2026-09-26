import XCTest
@testable import ListenToMe

/// `HistoryStore.removeLegacyBackup` fixes the plaintext `history.json.bak`
/// left behind by the legacy NDJSON migration surviving indefinitely even
/// after a user turns on "encrypt history at rest" — that backup held the
/// user's whole pre-migration history in plaintext regardless of the
/// setting. Drives the static core directly against a temp dir so it
/// doesn't touch real Preferences or the main `history.ndjson`.
final class HistoryLegacyBackupTests: XCTestCase {

    private var dir: URL!
    private var legacyURL: URL!
    private var ndjsonURL: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-legacy-backup-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        legacyURL = dir.appendingPathComponent("history.json")
        ndjsonURL = dir.appendingPathComponent("history.ndjson")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private var backupURL: URL { legacyURL.appendingPathExtension("bak") }

    func test_encryptionEnabled_bakExists_isRemoved() {
        try! "old plaintext history".data(using: .utf8)!.write(to: backupURL)

        HistoryStore.removeLegacyBackup(near: legacyURL, encryptionEnabled: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func test_encryptionDisabled_bakIsKept() {
        try! "old plaintext history".data(using: .utf8)!.write(to: backupURL)

        HistoryStore.removeLegacyBackup(near: legacyURL, encryptionEnabled: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func test_encryptionEnabled_noBak_noError() {
        // Should just be a silent no-op — nothing to assert beyond "doesn't
        // throw / crash".
        HistoryStore.removeLegacyBackup(near: legacyURL, encryptionEnabled: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func test_ndjsonUntouched_inAllCases() {
        let ndjsonData = "{\"id\":\"x\"}\n".data(using: .utf8)!
        try! ndjsonData.write(to: ndjsonURL)
        try! "old plaintext history".data(using: .utf8)!.write(to: backupURL)

        HistoryStore.removeLegacyBackup(near: legacyURL, encryptionEnabled: true)
        XCTAssertEqual(try? Data(contentsOf: ndjsonURL), ndjsonData)

        try! "old plaintext history".data(using: .utf8)!.write(to: backupURL)
        HistoryStore.removeLegacyBackup(near: legacyURL, encryptionEnabled: false)
        XCTAssertEqual(try? Data(contentsOf: ndjsonURL), ndjsonData)
    }
}
