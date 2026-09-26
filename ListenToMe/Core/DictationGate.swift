import Foundation

/// Which pipeline phases accept a new hotkey press / an auto-reset to idle.
/// Pure and testable: the races this guards against (a press starting a
/// second recording mid-transcription, an auto-reset firing over a live
/// recording) are timing bugs, so the decision itself needs to be checkable
/// without a live AppDelegate.
enum DictationGate {
    /// Presses are ignored while recording (already live) and while
    /// transcribing (short, ~1s; starting a second recording here used to
    /// strand the mic once the first transcription finished and clobbered
    /// `state.phase`).
    static func acceptsPress(in phase: Phase) -> Bool {
        switch phase {
        case .recording, .transcribing:
            return false
        default:
            return true
        }
    }

    /// Auto-reset must never yank an active recording/transcription (or the
    /// correction popover / suggestion banner) back to idle.
    static func allowsAutoReset(in phase: Phase) -> Bool {
        switch phase {
        case .recording, .transcribing, .correcting, .suggestion:
            return false
        default:
            return true
        }
    }
}
