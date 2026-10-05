import XCTest
@testable import ListenToMe

/// Tests for `PillErrorAction`: the mapping from pill error messages to a
/// one-click recovery. Pure logic, no stores.
final class PillErrorActionTests: XCTestCase {

    func test_micMessage_mapsToOpenMicrophoneSettings() {
        XCTAssertEqual(PillErrorAction.forMessage("Mic permission needed"), .openMicrophoneSettings)
    }

    func test_modelMissing_mapsToOpenApp() {
        XCTAssertEqual(PillErrorAction.forMessage("Model missing"), .openApp)
    }

    func test_unmappedMessage_returnsNil() {
        XCTAssertNil(PillErrorAction.forMessage("Couldn't apply correction"))
    }

    func test_hints() {
        XCTAssertEqual(PillErrorAction.openMicrophoneSettings.hint, "Open Settings")
        XCTAssertEqual(PillErrorAction.openApp.hint, "Open app")
    }
}
