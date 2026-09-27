import XCTest
@testable import ListenToMe

/// Guards `RuntimeEnvironment.resolveAppSupportDirectory`: the production
/// path (isRunningUnderTests: false) must stay byte-for-byte identical to
/// what every store computed before file-store test isolation existed —
/// `~/Library/Application Support/ListenToMe`. A regression here would
/// silently move a real user's data files on their next launch.
final class RuntimeEnvironmentTests: XCTestCase {

    func test_resolveAppSupportDirectory_productionPath_matchesHistoricalComputation() {
        let expected = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe", isDirectory: true)

        let actual = RuntimeEnvironment.resolveAppSupportDirectory(isRunningUnderTests: false)

        XCTAssertEqual(actual, expected)
    }

    func test_resolveAppSupportDirectory_underTests_isNotTheRealDirectory() {
        let real = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe", isDirectory: true)

        let testDir = RuntimeEnvironment.resolveAppSupportDirectory(isRunningUnderTests: true)

        XCTAssertNotEqual(testDir, real)
        XCTAssertTrue(testDir.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    func test_appSupportDirectory_isNeverTheRealDirectory_whileRunningUnderTests() {
        // Guard test mirroring PreferencesTestIsolationTests: while an
        // actual XCTest run is in progress, the shared property must never
        // resolve to the real Application Support directory.
        let real = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListenToMe", isDirectory: true)

        XCTAssertTrue(RuntimeEnvironment.isRunningUnderTests, "precondition: this test must itself run under XCTest")
        XCTAssertNotEqual(RuntimeEnvironment.appSupportDirectory, real)
    }
}
