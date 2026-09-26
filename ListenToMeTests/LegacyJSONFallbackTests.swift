import XCTest
@testable import ListenToMe

/// `LegacyJSONFallback.read` fixes SnippetsStore/TransformsStore losing
/// data silently: after a successful migration the legacy JSON is renamed
/// to `.json.bak`, so a later DB failure reading the un-renamed path found
/// nothing and showed an empty list even though the user's data was sitting
/// right there in the `.bak` copy.
final class LegacyJSONFallbackTests: XCTestCase {

    private var dir: URL!
    private var legacyURL: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-json-fallback-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        legacyURL = dir.appendingPathComponent("snippets.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private var backupURL: URL { legacyURL.appendingPathExtension("bak") }

    func test_onlyPrimary_returnsPrimaryData() {
        let data = "primary".data(using: .utf8)!
        try! data.write(to: legacyURL)

        XCTAssertEqual(LegacyJSONFallback.read(legacyURL: legacyURL), data)
    }

    func test_onlyBak_returnsBakData() {
        let data = "backup".data(using: .utf8)!
        try! data.write(to: backupURL)

        XCTAssertEqual(LegacyJSONFallback.read(legacyURL: legacyURL), data)
    }

    func test_bothExist_primaryWins() {
        let primary = "primary".data(using: .utf8)!
        let backup = "backup".data(using: .utf8)!
        try! primary.write(to: legacyURL)
        try! backup.write(to: backupURL)

        XCTAssertEqual(LegacyJSONFallback.read(legacyURL: legacyURL), primary)
    }

    func test_neitherExists_returnsNil() {
        XCTAssertNil(LegacyJSONFallback.read(legacyURL: legacyURL))
    }
}
