import XCTest
@testable import ListenToMe

/// `PasteTarget.decide` is the fix for pasting a cleaned dictation into
/// whatever app happens to be frontmost once cleanup finishes (including a
/// password field), rather than the app the user was actually dictating
/// into. Pure decision table, no AX/pasteboard access needed.
final class PasteTargetTests: XCTestCase {

    func test_secureInput_beatsEverything() {
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: "com.apple.Notes",
                               currentBundleId: "com.apple.Notes",
                               secureInputActive: true),
            .block)
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: nil,
                               currentBundleId: nil,
                               secureInputActive: true),
            .block)
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: "com.apple.Notes",
                               currentBundleId: "com.other.app",
                               secureInputActive: true),
            .block)
    }

    func test_nilExpected_pastes() {
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: nil,
                               currentBundleId: "com.apple.Notes",
                               secureInputActive: false),
            .paste)
    }

    func test_nilCurrent_withNonNilExpected_copiesInstead() {
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: "com.apple.Notes",
                               currentBundleId: nil,
                               secureInputActive: false),
            .copyInstead)
    }

    func test_sameApp_pastes() {
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: "com.apple.TextEdit",
                               currentBundleId: "com.apple.TextEdit",
                               secureInputActive: false),
            .paste)
    }

    func test_differentApp_copiesInstead() {
        XCTAssertEqual(
            PasteTarget.decide(expectedBundleId: "com.apple.TextEdit",
                               currentBundleId: "com.apple.Terminal",
                               secureInputActive: false),
            .copyInstead)
    }
}
