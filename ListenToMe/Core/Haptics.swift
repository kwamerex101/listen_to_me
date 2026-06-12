import AppKit

/// Thin wrapper around NSHapticFeedbackManager.
/// No-op on Macs without a Force Touch trackpad.
enum Haptics {
    /// Fired when recording starts — a firm, noticeable tap.
    static func start() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }

    /// Fired when recording ends — a lighter confirmation tap.
    static func stop() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    /// Fired when transcription + cleanup succeed and text is pasted.
    /// `.drawCompleted` defers the tap to the next screen update so it
    /// lands on the same frame the success visuals (checkmark/halo)
    /// start, reading as one event instead of haptic-then-animation.
    static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .drawCompleted
        )
    }

    /// Fired when a dictation fails — balances the success tap so a failure
    /// is felt, not just seen. `.levelChange` is the firmest available tap.
    static func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
}
