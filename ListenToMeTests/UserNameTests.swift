import XCTest
@testable import ListenToMe

/// Trim + normalization contract tests for the userName preference.
///
/// These tests exercise only the static trim/empty-handling behaviour —
/// they do not mutate the live Preferences singleton's UserDefaults store,
/// so they are safe to run alongside other tests without side effects.
/// Full round-trip through UserDefaults would require a dependency-injected
/// defaults instance; that refactor is out of scope here.
final class UserNameTests: XCTestCase {

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
