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
    static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
}
