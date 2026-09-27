import Foundation
import XCTest
@testable import ListenToMe

/// Tests for the Sparkle auto-update configuration baked into Info.plist by
/// `project.yml` (`info.properties`). The test host is the app itself, so
/// `Bundle.main` here is ListenToMe's own bundle (same pattern as
/// `ModelIntegrityTests` and friends reading real app config).
final class UpdaterConfigTests: XCTestCase {

    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    func test_feedURL_is_https_and_points_at_latest_appcast_asset() {
        guard let feedURL = info["SUFeedURL"] as? String else {
            XCTFail("SUFeedURL missing from Info.plist")
            return
        }
        XCTAssertTrue(feedURL.hasPrefix("https://"))
        XCTAssertTrue(feedURL.hasSuffix("/releases/latest/download/appcast.xml"))
    }

    /// SUEnableAutomaticChecks must be ABSENT so Sparkle shows its own
    /// one-time consent prompt (on the second launch) instead of checking
    /// for updates before the user has agreed to it.
    func test_automaticChecks_key_is_absent_so_consent_prompt_shows() {
        XCTAssertNil(info["SUEnableAutomaticChecks"],
                     "SUEnableAutomaticChecks must be absent, or Sparkle skips the consent prompt")
    }

    func test_systemProfiling_is_disabled() {
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
    }

    /// An EdDSA (Ed25519) public key is exactly 32 raw bytes, base64-encoded.
    /// Guards against a missing, truncated or placeholder `SUPublicEDKey`:
    /// Sparkle would reject every update, so no build may ship with one.
    func test_publicEDKey_decodes_to_32_bytes() {
        guard let key = info["SUPublicEDKey"] as? String else {
            XCTFail("SUPublicEDKey missing from Info.plist")
            return
        }
        guard let data = Data(base64Encoded: key) else {
            XCTFail("SUPublicEDKey \"\(key)\" is not valid base64")
            return
        }
        XCTAssertEqual(data.count, 32,
                        "SUPublicEDKey must decode to exactly 32 bytes (Ed25519); got \(data.count)")
    }

    @MainActor
    func test_updaterIsNotStartedUnderTests() {
        // Sparkle must stay idle inside the test host: no scheduler, no
        // consent prompt, no network. An unstarted updater can't check.
        XCTAssertTrue(Updater.isRunningUnderTests)
        XCTAssertFalse(Updater.shared.canCheck)
    }
}
