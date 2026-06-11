import XCTest
@testable import ListenToMe

/// Tests for the secure-input guard that blocks dictation insertion into
/// password fields. The live `IsSecureEventInputEnabled()` / AX-role reads
/// can't be exercised in a unit test, so we cover the pure role check and the
/// `testOverride` seam that the pipeline guard ultimately consults.
final class SecureInputTests: XCTestCase {

    override func tearDown() {
        SecureInput.testOverride = nil
        super.tearDown()
    }

    // MARK: - isSecureRole

    func test_secureTextFieldRole_isSecure() {
        XCTAssertTrue(SecureInput.isSecureRole("AXSecureTextField"))
    }

    func test_plainTextFieldRole_isNotSecure() {
        XCTAssertFalse(SecureInput.isSecureRole("AXTextField"))
        XCTAssertFalse(SecureInput.isSecureRole("AXTextArea"))
    }

    func test_nilRole_isNotSecure() {
        // AX read failure must NOT block legitimate dictation.
        XCTAssertFalse(SecureInput.isSecureRole(nil))
    }

    func test_role_matches_published_constant() {
        XCTAssertEqual(SecureInput.secureFieldRole, "AXSecureTextField")
    }

    // MARK: - isActive override seam

    func test_override_true_forcesActive() {
        SecureInput.testOverride = true
        XCTAssertTrue(SecureInput.isActive)
    }

    func test_override_false_forcesInactive() {
        // false override short-circuits before any live system query.
        SecureInput.testOverride = false
        XCTAssertFalse(SecureInput.isActive)
    }

    // MARK: - Paster.replace secure-input guard

    @MainActor
    func test_paster_replace_refuses_when_secure() {
        // When secure input is active, replace must bail (nil) before any
        // pasteboard mutation or keystroke — backtrack then falls through to
        // the pipeline guard. Token values are arbitrary; the guard fires first.
        SecureInput.testOverride = true
        let token = PasteToken(
            bundleId: "com.example.app",
            changeCountAtPaste: NSPasteboard.general.changeCount,
            pastedText: "original",
            priorPasteboardString: nil,
            timestamp: Date(),
            selection: nil
        )
        XCTAssertNil(Paster.replace(with: "revised", token: token))
    }
}
