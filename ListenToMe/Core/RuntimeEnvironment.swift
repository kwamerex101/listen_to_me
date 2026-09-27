import Foundation

/// Central place to detect "are we running inside the XCTest host".
///
/// The unit test target runs inside the app itself (TEST_HOST), so
/// `ProcessInfo`'s environment carries `XCTestConfigurationFilePath`
/// whenever a test run launched us. Anything that shouldn't run for real
/// during a test — starting Sparkle's updater, touching the user's real
/// UserDefaults domain, popping onboarding UI — checks this first.
enum RuntimeEnvironment {
    static let isRunningUnderTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Directory ListenToMe's own data files live in: `store.sqlite`,
    /// `history.ndjson`, `dictionary.json`, `dictionary-candidates.json`,
    /// `styles.json`, `style-samples.json`, `whisper-server.pid`, and the
    /// legacy JSON files some of those migrated from. Production value is
    /// unchanged: `~/Library/Application Support/ListenToMe`. Under tests
    /// (TEST_HOST) this is a fresh temp directory instead, created once per
    /// process, so a test run never reads or writes the developer's real
    /// data (see the incident this class of bug already caused for
    /// UserDefaults, above).
    static let appSupportDirectory: URL =
        resolveAppSupportDirectory(isRunningUnderTests: isRunningUnderTests)

    /// Pure function behind `appSupportDirectory`. Exists so a test can
    /// assert the production path is computed exactly as before this fix
    /// (see RuntimeEnvironmentTests) without actually needing to run under
    /// tests to check it.
    internal static func resolveAppSupportDirectory(isRunningUnderTests: Bool) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let real = base.appendingPathComponent("ListenToMe", isDirectory: true)
        guard isRunningUnderTests else { return real }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListenToMeTests-\(ProcessInfo.processInfo.processIdentifier)",
                                     isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
