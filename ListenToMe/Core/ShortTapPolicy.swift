import Foundation

/// Decides whether a short hotkey tap should open the correction popover.
///
/// A short tap always starts (and then discards) a brief recording, so by
/// the time the decision runs the current phase is no longer meaningful,
/// it reflects the just-discarded tap, not the dictation before it. The
/// decision instead looks at `phaseAtPress`, the phase captured the instant
/// before the press did anything. Correction only makes sense when the
/// PREVIOUS dictation actually finished and pasted something: `.polishing`
/// doesn't qualify because clean-first hasn't pasted anything yet, so
/// opening correction there would edit the token from the dictation before
/// that one.
enum ShortTapPolicy {
    static func opensCorrection(phaseAtPress: Phase, hasPasteToken: Bool) -> Bool {
        guard hasPasteToken else { return false }
        switch phaseAtPress {
        case .success:
            return true
        default:
            return false
        }
    }
}
