import Foundation
import SwiftUI

enum Phase: Equatable {
    case idle
    case recording
    case transcribing
    /// Legacy: only entered if the streaming-preview flow is bypassed.
    /// Kept so existing switch statements stay exhaustive.
    case cleaning
    /// Raw transcript is already pasted into the target app; cleanup is
    /// running in the background and may swap in a polished version.
    case polishing(rawPreview: String)
    case success(preview: String)
    case error(message: String)
    /// Inline correction popover is open — user is editing the just-pasted
    /// text. Pill goes neutral; the actual UI lives in `CorrectionWindow`.
    case correcting
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: Phase = .idle
    @Published var level: Float = 0          // 0…1, updated ~30Hz during recording
    @Published var lastTranscript: String = ""
    @Published var hotkeyGranted: Bool = false
    @Published var micGranted: Bool = false
    @Published var showPermissionPrompt: Bool = false
    /// True if the `claude` CLI resolves on PATH. Default true (optimistic);
    /// set on launch by an `isAvailable()` probe. Drives the menu warning
    /// when cleanup is enabled but the binary is missing.
    @Published var claudeAvailable: Bool = true

    /// Called by the "Dictate now" button — same behavior as pressing the hotkey.
    var onStartTap: (() -> Void)?
    /// Called by pill's stop button — same behavior as releasing the hotkey.
    var onStopTap: (() -> Void)?
    /// Called by pill's X button — abort recording without transcribing.
    var onCancelTap: (() -> Void)?
    /// Called when the user clicks the pill in success/polishing — opens
    /// the inline correction popover.
    var onPillTap: (() -> Void)?

    private init() {}
}
