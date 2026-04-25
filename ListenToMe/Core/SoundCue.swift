import AppKit

/// Plays subtle system sounds at recording boundaries.
/// Uses NSSound so no asset files are needed.
enum SoundCue {
    /// Short ping when recording starts.
    static func recordingStart() {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    /// Softer chime when recording stops and transcription begins.
    static func recordingStop() {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    /// Brighter chime on successful paste.
    static func success() {
        guard Preferences.shared.soundEnabled else { return }
        NSSound(named: "Glass")?.play()
    }
}
