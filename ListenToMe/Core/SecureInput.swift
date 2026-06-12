import Carbon.HIToolbox
import ApplicationServices

/// Detects when inserting dictated text would be unsafe — chiefly when a
/// password field has focus. Dictation always produces a transcript from the
/// mic, but if the user is plainly entering a secret, pasting it as plaintext
/// into the field (or recording it in history) would leak it.
///
/// Two complementary signals, either of which blocks insertion:
///
/// 1. `IsSecureEventInputEnabled()` — macOS sets this process-wide whenever a
///    secure text field has focus (login window, Keychain prompts, most
///    password managers, `sudo` in Terminal). Catches the common case.
/// 2. AX role `AXSecureTextField` on the focused element — catches web-form
///    password inputs where the browser doesn't always flip secure event
///    input globally.
enum SecureInput {
    /// The AX role string macOS reports for a secure (password) text field.
    /// Not exposed as a typed constant in the Swift AX bindings, so we match
    /// the literal — same value as `kAXSecureTextFieldRole`.
    static let secureFieldRole = "AXSecureTextField"

    /// Test seam. When non-nil, `isActive` returns this instead of querying
    /// live system state. Reset to nil in test teardown.
    static var testOverride: Bool?

    /// True when text insertion must be blocked.
    static var isActive: Bool {
        if let testOverride { return testOverride }
        if IsSecureEventInputEnabled() { return true }
        return focusedElementIsSecure()
    }

    /// Pure role check, pulled out so it can be unit-tested without a live
    /// AX tree. nil (read failed) or any non-secure role → not secure.
    static func isSecureRole(_ role: String?) -> Bool {
        role == secureFieldRole
    }

    /// Reads the system-wide focused element's AX role and reports whether it
    /// is a secure text field. Returns false on any AX failure — the global
    /// `IsSecureEventInputEnabled()` check is the primary guard, so a failed
    /// read here must never block legitimate dictation.
    private static func focusedElementIsSecure() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef else { return false }

        let element = focusedRef as! AXUIElement
        // 0.5 SECONDS (Float, not ms). Set per-element, not on systemWide,
        // mirroring Paster.captureSelectionState.
        AXUIElementSetMessagingTimeout(element, 0.5)

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef
        ) == .success else { return false }

        return isSecureRole(roleRef as? String)
    }
}
