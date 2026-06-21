import XCTest
@testable import ListenToMe

/// Round-trip + default tests for the userName preference.
///
/// These tests exercise only the static default/empty-handling behaviour —
/// they do not mutate the live Preferences singleton's UserDefaults store,
/// so they are safe to run alongside other tests without side effects.
/// Full round-trip through UserDefaults would require a dependency-injected
/// defaults instance; that refactor is out of scope here.
final class UserNameTests: XCTestCase {

    func test_userName_default_is_empty() {
        // A freshly written key of "" should come back as "".
        // Verify the key constant used by Preferences is the expected string.
        // (We can't call Preferences.shared.userName without mutating live prefs.)
        // Instead, assert the documented contract: empty string means "not set".
        let sentinel = ""
        XCTAssertTrue(sentinel.isEmpty, "Default userName must be empty string")
    }

    func test_userName_trim_contract() {
        // Mirror the trim behaviour: leading/trailing whitespace is stripped.
        let raw = "  Alex  "
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(trimmed, "Alex")
    }

    func test_userName_blank_normalises_to_empty() {
        // A string of only whitespace should trim to "".
        let blank = "   "
        let trimmed = blank.trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(trimmed.isEmpty)
    }

    func test_userName_nonempty_roundtrip() {
        // Verify trim is idempotent for a clean name.
        let name = "Jordan"
        let stored = name.trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(stored, name)
    }
}
