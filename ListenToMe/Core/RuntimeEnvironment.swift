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
}
