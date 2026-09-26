import Foundation

/// Decides what to do with a cleaned dictation once cleanup finishes.
/// Cleanup can take several seconds, so the app the user was in when they
/// started dictating isn't necessarily the app in front now — and if a
/// secure field (password) has focus, the target shouldn't matter at all.
/// Pure so it's testable without AX/pasteboard access.
enum PasteTarget {
    enum Decision: Equatable {
        /// Same app as when dictation started (or the original app is
        /// unknown) — paste as usual.
        case paste
        /// The frontmost app changed since dictation started — don't paste
        /// into whatever's there now; copy to the clipboard instead.
        case copyInstead
        /// A secure field has focus right now — never insert, never store.
        case block
    }

    /// `expectedBundleId`: the frontmost app's bundle id when dictation
    /// started (nil if it couldn't be resolved then).
    /// `currentBundleId`: the frontmost app's bundle id right now.
    /// `secureInputActive`: whether a secure-event-input context (password
    /// field) has focus right now.
    static func decide(expectedBundleId: String?, currentBundleId: String?,
                       secureInputActive: Bool) -> Decision {
        if secureInputActive { return .block }
        guard let expectedBundleId else { return .paste }
        return currentBundleId == expectedBundleId ? .paste : .copyInstead
    }
}
